import AppKit
import SwiftUI

/// Home Canvas (J1): primary card = New Agent Session, secondary = Plain
/// Terminal. No theme picker, no account, no network. Providers are whatever
/// PATH detects — anything else goes through Custom Command.
struct HomeView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                Text("sill")
                    .font(T.mono(34, .medium))
                    .foregroundStyle(T.fg)
                Text("the attention surface for agents")
                    .font(T.ui(13))
                    .foregroundStyle(T.subtle)
            }
            .padding(.bottom, 40)

            HStack(spacing: 14) {
                HomeCard(
                    title: "New Agent Session",
                    subtitle: "claude · codex · grok — detected on PATH",
                    agent: "claude",
                    primary: true,
                    action: { appState.showNewSession = true }
                )
                HomeCard(
                    title: "Plain Terminal",
                    subtitle: "login shell in any directory",
                    agent: nil,
                    primary: false,
                    action: { newPlainTerminal() }
                )
            }
            .padding(.horizontal, 48)
            .frame(maxWidth: 720)

            Spacer()
            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.bg)
    }

    private func newPlainTerminal() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let pane = Pane(title: "Terminal", cwd: home, argv: [shell, "-l"])
        appState.addPane(pane)
        pane.surface = SwiftTermSurface(pane: pane, appState: appState)
        try? pane.surface?.spawn()
    }
}

struct HomeCard: View {
    let title: String
    let subtitle: String
    let agent: String?
    let primary: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                GlyphTile(agent: agent, size: 26,
                          tinted: primary ? T.accent : T.subtle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(T.ui(14, .medium))
                        .foregroundStyle(T.fg)
                    Text(subtitle)
                        .font(T.ui(11))
                        .foregroundStyle(T.subtle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(hovering ? T.rowHover : T.surface)
            .overlay(
                RoundedRectangle(cornerRadius: T.radiusMd)
                    .stroke(primary ? T.accent.opacity(0.55) : T.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: T.radiusMd))
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(SillCardStyle())
        .onHover { hovering = $0 }
    }
}
