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
                Divider()
            }
            if let pane = appState.focused {
                PaneContainer(pane: pane, appState: appState)
            } else {
                ContentUnavailableView("No session focused",
                                       systemImage: "terminal",
                                       description: Text("⌘N for a new session"))
            }
        }
    }
}

struct PaneContainer: View {
    @ObservedObject var pane: Pane
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            titleStrip
            Divider()
            surfaceBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !appState.terminalMode {
                ComposerView(pane: pane)
            }
        }
        // V2: the ring wraps a blocked surface — 2px, static, no pulse loop.
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor, lineWidth: pane.status.isBlocked ? 2 : 0)
                .animation(.easeOut(duration: 0.12), value: pane.status.isBlocked)
                .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private var surfaceBody: some View {
        if pane.viewMode == .transcript && !pane.altScreen {
            TranscriptView(pane: pane)
        } else if let surface = pane.surface {
            SurfaceNSView(surface: surface)
        } else if let err = pane.spawnError {
            errorStrip(err)
        } else {
            ProgressView().controlSize(.small).padding()
        }
    }

    private var titleStrip: some View {
        HStack(spacing: 8) {
            Text(pane.title).font(.system(size: 12, weight: .medium))
            Text(pane.cwd.path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if pane.altScreen {
                Text("TUI — raw locked").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Picker("", selection: $pane.viewMode) {
                Text("Raw").tag(ViewMode.raw)
                Text("Transcript").tag(ViewMode.transcript)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            .disabled(pane.altScreen) // alt-screen locks the toggle (FR-006)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func errorStrip(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24)).foregroundStyle(.secondary)
            Text(msg).font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Retry") {
                pane.spawnError = nil
                pane.surface = SwiftTermSurface(pane: pane, appState: appState)
                try? pane.surface?.spawn()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Transcript (V3): read-only structured event layer. No events → honest
/// empty state suggesting Raw — never synthesized bubbles.
struct TranscriptView: View {
    @ObservedObject var pane: Pane

    var body: some View {
        if pane.transcript.isEmpty {
            VStack(spacing: 8) {
                Text("No structured events yet")
                    .font(.system(size: 13, weight: .medium))
                Text("This view fills from OSC 7501/133 and hook events.\nSwitch to Raw for the live terminal.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(pane.transcript.reversed()) { ev in
                HStack(alignment: .top, spacing: 8) {
                    Text(ev.ts, style: .time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 70, alignment: .leading)
                    Text(ev.text)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                }
            }
            .listStyle(.plain)
        }
    }
}
