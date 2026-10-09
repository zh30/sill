import AppKit
import SwiftUI

/// Composer (V4): a docked input bar — multiline, undo/redo, `Enter` newline,
/// `Cmd+Enter` sends as bracketed paste into the pane's PTY, `Esc` hands focus
/// back to the terminal. Minimum 72px, hugs the bottom, never a bubble.
struct ComposerView: View {
    @ObservedObject var pane: Pane
    @State private var confirmSend = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ComposerTextView(
                text: $pane.composerDraft,
                pane: pane,
                onSend: { send() },
                onEscape: { pane.surface?.focusPty() }
            )
            .frame(minHeight: 72, maxHeight: 160)
            HStack {
                Text("⏎ newline · ⌘⏎ send · esc → terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Send") { send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Text contains control characters", isPresented: $confirmSend) {
            Button("Send anyway") { reallySend() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The draft contains ESC or control bytes. Sending writes them into the PTY as-is.")
        }
    }

    private func send() {
        guard !pane.composerDraft.isEmpty else { return }
        // Control characters get a confirm; cancel writes nothing (FR-007).
        if pane.composerDraft.contains(where: { $0 == "\u{1b}" || ($0.isASCII && $0.asciiValue! < 0x20 && $0 != "\n" && $0 != "\t") }) {
            confirmSend = true
            return
        }
        reallySend()
    }

    private func reallySend() {
        guard let surface = pane.surface as? SwiftTermSurface else { return }
        surface.writePasted(pane.composerDraft + "\n")
        pane.record(.command, "composer → pty (\(pane.composerDraft.count) chars)")
        pane.composerDraft = ""
        if pane.status.isBlocked { pane.status = .working }
    }
}

/// NSTextView so Cmd+Enter / Esc are real key handling, not SwiftUI guesses.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var pane: Pane
    var onSend: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let textView = ComposerNSTextView()
        textView.onSend = onSend
        textView.onEscape = onEscape
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        // Blocked + focused pane hands input to the composer (G3/J2).
        context.coordinator.focusObserver = NotificationCenter.default.addObserver(
            forName: .sillFocusComposer, object: nil, queue: .main
        ) { [weak textView, weak pane] note in
            guard note.object as? Pane === pane else { return }
            textView?.window?.makeFirstResponder(textView)
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        tv.onSend = onSend
        tv.onEscape = onEscape
        if tv.string != text { tv.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: ComposerNSTextView?
        var focusObserver: NSObjectProtocol?
        init(_ parent: ComposerTextView) {
            self.parent = parent
        }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }

    final class ComposerNSTextView: NSTextView {
        var onSend: (() -> Void)?
        var onEscape: (() -> Void)?
        weak var coordinator: Coordinator?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36, event.modifierFlags.contains(.command) {
                onSend?()
                return
            }
            if event.keyCode == 53 { // Esc → PTY
                onEscape?()
                return
            }
            super.keyDown(with: event)
        }

        override func didChangeText() {
            super.didChangeText()
            (delegate as? Coordinator)?.parent.text = string
        }
    }
}
