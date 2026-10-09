import SwiftUI

/// Palette (V7, FR-015): Cmd+Shift+P command runner over the P0 verbs.
/// Keyboard-first: ↑/↓ move, ↵ runs, esc dismisses — a palette you can't
/// drive without the mouse isn't one.
struct PaletteView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = 0

    struct Command: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let shortcut: String?
        let run: (AppState) -> Void

        init(_ title: String, icon: String, shortcut: String? = nil,
             run: @escaping (AppState) -> Void) {
            self.title = title
            self.icon = icon
            self.shortcut = shortcut
            self.run = run
        }
    }

    private var commands: [Command] {
        [
            Command("New Agent Session", icon: "plus.rectangle", shortcut: "⌘N") { $0.showNewSession = true },
            Command("New Terminal", icon: "apple.terminal", shortcut: "⌘T") { st in st.post(.sillNewTerminal) },
            Command("Toggle Raw / Transcript", icon: "text.alignleft") { st in
                guard let p = st.focused, !p.altScreen else { return }
                p.viewMode = p.viewMode == .raw ? .transcript : .raw
            },
            Command("Toggle Rail", icon: "sidebar.left", shortcut: "⌘B") { $0.railCollapsed.toggle() },
            Command("Terminal Mode", icon: "rectangle.expand.vertical") { $0.terminalMode.toggle() },
            Command("Jump to Unread Blocked", icon: "bell.badge", shortcut: "⌘'") { _ = $0.jumpToOldestBlocked() },
            Command("Import Ghostty Config", icon: "square.and.arrow.down") { _ in
                // Report lives in the CLI (`sill import ghostty`); deep-link
                // into it so the surface stays a thin mirror.
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["-a", "Terminal", "sill import ghostty"]
                try? task.run()
            },
            Command("Export Layout", icon: "square.and.arrow.up") { _ in
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["-a", "Terminal", "sill export layout"]
                try? task.run()
            },
            Command("Close Pane", icon: "xmark.rectangle", shortcut: "⌘W") { st in
                if let p = st.focused { st.closePane(p) }
            },
        ]
    }

    private var filtered: [Command] {
        query.isEmpty ? commands
            : commands.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .font(T.ui(11, .medium))
                    .foregroundStyle(T.faint)
                PaletteField(query: $query,
                             onArrow: { move($0) },
                             onReturn: { runSelection() },
                             onEscape: { dismiss() })
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            Divider().overlay(T.borderSoft)
            if filtered.isEmpty {
                Text("No commands match \"\(query)\"")
                    .font(T.ui(12))
                    .foregroundStyle(T.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                List(Array(filtered.enumerated()), id: \.element.id) { i, cmd in
                    HStack(spacing: 10) {
                        Image(systemName: cmd.icon)
                            .font(T.ui(11))
                            .foregroundStyle(i == selection ? T.fg : T.faint)
                            .frame(width: 16, alignment: .center)
                        Text(cmd.title)
                            .font(T.ui(12))
                            .foregroundStyle(i == selection ? T.fg : T.fg.opacity(0.85))
                        Spacer()
                        if let sc = cmd.shortcut {
                            Text(sc)
                                .font(T.mono(10))
                                .foregroundStyle(T.faint)
                        }
                    }
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(i == selection ? T.rowHover : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = i; runSelection() }
                    .onHover { h in if h { selection = i } }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: min(CGFloat(filtered.count) * 30 + 8, 280))
            }
        }
        .frame(width: 400)
        .background(T.surface)
        .overlay(RoundedRectangle(cornerRadius: T.radiusMd).stroke(T.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: T.radiusMd))
        .onChange(of: query) { _, _ in selection = 0 }
        .onChange(of: filtered.count) { _, n in selection = min(selection, max(0, n - 1)) }
    }

    private func move(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selection = (selection + delta + filtered.count) % filtered.count
    }

    private func runSelection() {
        guard filtered.indices.contains(selection) else { return }
        let cmd = filtered[selection]
        dismiss()
        cmd.run(appState)
    }
}

/// NSTextField so ↑/↓/↵/esc are real key handling inside the field editor —
/// SwiftUI's onKeyPress on a TextField loses to the editor's own map.
private struct PaletteField: NSViewRepresentable {
    @Binding var query: String
    var onArrow: (Int) -> Void
    var onReturn: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> PaletteNSTextField {
        let field = PaletteNSTextField()
        field.handler = context.coordinator
        field.placeholderString = "jump to command…"
        field.isBordered = false
        field.drawsBackground = false
        field.font = NSFont.systemFont(ofSize: 13)
        field.focusRingType = .none
        field.delegate = context.coordinator
        context.coordinator.field = field
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ nsView: PaletteNSTextField, context: Context) {
        if nsView.stringValue != query { nsView.stringValue = query }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PaletteField
        weak var field: PaletteNSTextField?
        init(_ parent: PaletteField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            parent.query = f.stringValue
        }

        /// Editing keys reach the field editor, not the NSTextField — the
        /// delegate's doCommandBy is the interception point for ↑/↓/↵/esc.
        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onArrow(-1); return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onArrow(1); return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onReturn(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape(); return true
            default:
                return false
            }
        }
    }
}

private final class PaletteNSTextField: NSTextField {
    weak var handler: PaletteField.Coordinator?
}

extension AppState {
    func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: self)
    }
}
