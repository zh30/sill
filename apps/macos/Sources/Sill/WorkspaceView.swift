import SwiftUI

/// Agent Workspace (P0 IA): rail + title strip + surface body + composer dock.
/// The surface body is one pane at a time (Surface Stack); the Focus Ring
/// wraps a blocked surface only (V2: 2px, never blinking).
struct WorkspaceView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            if !appState.terminalMode {
                RailView(appState: appState)
                Divider().overlay(T.borderSoft)
            }
            if let pane = appState.focused {
                // .id forces a fresh view tree per pane — without it SwiftUI
                // reuses the mounted NSViewRepresentables and the surface /
                // composer stay bound to the previously focused pane.
                PaneContainer(pane: pane, appState: appState)
                    .id(pane.id)
            } else {
                EmptyState(icon: "terminal",
                           title: "No session focused",
                           hint: "⌘N new session · ⌘⇧P commands")
            }
        }
        .background(T.bg)
    }
}

struct PaneContainer: View {
    @ObservedObject var pane: Pane
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            titleStrip
            Divider().overlay(T.borderSoft)
            surfaceBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !appState.terminalMode {
                ComposerView(pane: pane)
            }
        }
        // V2: the ring wraps a blocked surface — 2px, static, no pulse loop.
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(T.accent, lineWidth: pane.status.isBlocked ? 2 : 0)
                .animation(.easeOut(duration: 0.12), value: pane.status.isBlocked)
                .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private var surfaceBody: some View {
        if pane.viewMode == .transcript && !pane.altScreen {
            TranscriptView(pane: pane)
        } else if let err = pane.spawnError {
            // Failed launch beats the (empty) surface — keep Retry visible.
            errorStrip(err)
        } else if let surface = pane.surface {
            SurfaceNSView(surface: surface)
        } else if pane.exited {
            errorStrip(pane.exitNote ?? "process exited")
        } else {
            ProgressView().controlSize(.small).padding()
        }
    }

    private var titleStrip: some View {
        HStack(spacing: 10) {
            GlyphTile(agent: pane.agent, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(pane.title)
                    .font(T.ui(12, .medium))
                    .foregroundStyle(T.fg)
                    .lineLimit(1)
            }
            // Title wins spare width but is capped — without a cap a long
            // title can starve cwd to zero width and its tooltip with it.
            .frame(maxWidth: 300, alignment: .leading)
            .layoutPriority(1)
            // cwd is the secondary cue — it yields width to the title and
            // truncates from the middle; the full path is on the tooltip.
            Text(pane.cwd.path)
                .font(T.mono(10))
                .foregroundStyle(T.faint)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(pane.cwd.path)
            Spacer()
            if pane.altScreen {
                Text("TUI — raw locked")
                    .font(T.ui(10))
                    .foregroundStyle(T.subtle)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(T.rowHover)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            ModePicker(mode: $pane.viewMode, locked: pane.altScreen)
            IconButton(symbol: "xmark", size: 20, symbolSize: 9, weight: .medium,
                       help: "Close pane (⌘W)") {
                appState.closePane(pane)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: T.stripHeight)
        .background(T.surface)
    }

    private func errorStrip(_ msg: String) -> some View {
        EmptyState(icon: "exclamationmark.triangle",
                   title: msg,
                   hint: pane.exited ? "The process has exited." : nil,
                   action: ("Retry / Respawn", {
                       pane.spawnError = nil
                       pane.exited = false
                       pane.exitNote = nil
                       pane.surface = SwiftTermSurface(pane: pane, appState: appState)
                       try? pane.surface?.spawn()
                   }))
    }
}

/// Raw / Transcript segmented control — a bordered capsule pair, not the
/// system segmented style (which drags in light-chrome assumptions).
struct ModePicker: View {
    @Binding var mode: ViewMode
    let locked: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment(.raw, "Raw")
            Rectangle()
                .fill(T.border)
                .frame(width: 1, height: 14)
            segment(.transcript, "Transcript")
        }
        .background(T.raised)
        .overlay(RoundedRectangle(cornerRadius: T.radiusSm).stroke(T.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: T.radiusSm))
        .opacity(locked ? 0.45 : 1)
        .disabled(locked) // alt-screen locks the toggle (FR-006)
        .help(locked ? "Alt-screen TUI forces Raw" : "Switch surface")
    }

    private func segment(_ m: ViewMode, _ label: String) -> some View {
        Button { mode = m } label: {
            Text(label)
                .font(T.ui(11, mode == m ? .medium : .regular))
                .foregroundStyle(mode == m ? T.fg : T.subtle)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(mode == m ? T.rowHover : .clear)
        }
        .buttonStyle(.plain)
    }
}

/// Transcript (V3): read-only structured event layer. No events → honest
/// empty state suggesting Raw — never synthesized bubbles. LazyVStack over
/// List: no inherited row chrome to fight, and the bottom sentinel gives
/// real at-bottom tracking for follow-scroll.
struct TranscriptView: View {
    @ObservedObject var pane: Pane
    /// Auto-follow only while the user is already at the bottom — a scroll
    /// up to read history must never get yanked back by new events.
    @State private var atBottom = true

    private static let minuteFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    /// Timestamps print only when the minute changes — a stream of events
    /// inside one minute doesn't need the same label repeated 40 times.
    private func showsTime(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = pane.transcript[index - 1]
        return Self.minuteFmt.string(from: prev.ts) != Self.minuteFmt.string(from: pane.transcript[index].ts)
    }

    var body: some View {
        if pane.transcript.isEmpty {
            EmptyState(icon: "text.alignleft",
                       title: "No structured events yet",
                       hint: "This view fills from OSC 7501/133 and hook events.\nSwitch to Raw for the live terminal.")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(pane.transcript.enumerated()), id: \.element.id) { index, ev in
                            TranscriptRow(ev: ev, showTime: showsTime(at: index))
                                .padding(.horizontal, 14)
                                .padding(.top, showsTime(at: index) && index > 0 ? 7 : 2)
                                .padding(.bottom, 2)
                        }
                        // Bottom sentinel: presence = the user sees the tail.
                        Color.clear
                            .frame(height: 1)
                            .id("transcript-bottom")
                            .onAppear { atBottom = true }
                            .onDisappear { atBottom = false }
                    }
                }
                .background(T.bg)
                .onChange(of: pane.transcript.count) { _, _ in
                    guard atBottom else { return }
                    withAnimation(nil) { proxy.scrollTo("transcript-bottom") }
                }
            }
        }
    }
}

struct TranscriptRow: View {
    let ev: Pane.TranscriptEvent
    var showTime = true

    private var kindLabel: String {
        switch ev.kind {
        case .status: return "status"
        case .command: return "command"
        case .cwd: return "cwd"
        case .notify: return "notify"
        case .progress: return "progress"
        }
    }

    /// Kind tint: attention-ish events get accent, plumbing stays zinc.
    private var kindColor: Color {
        switch ev.kind {
        case .status, .notify: return T.accent
        case .command: return T.fg
        case .progress: return T.subtle
        case .cwd: return T.faint
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(showTime ? ev.ts.formatted(date: .omitted, time: .shortened) : "")
                .font(T.mono(10))
                .foregroundStyle(T.faint)
                .frame(width: 62, alignment: .leading)
            Text(kindLabel)
                .font(T.mono(9))
                .foregroundStyle(kindColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(kindColor.opacity(0.4), lineWidth: 1))
                .frame(width: 64, alignment: .leading)
            Text(ev.text)
                .font(T.mono(11))
                .foregroundStyle(T.fg.opacity(0.85))
                .textSelection(.enabled)
        }
    }
}
