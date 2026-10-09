import AppKit
import SwiftUI

/// Home Canvas (J1): primary card = New Agent Session, secondary = Plain
/// Terminal. No theme picker, no account, no network. Providers are whatever
/// PATH detects — anything else goes through Custom Command.
struct HomeView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Text("Sill")
                    .font(.system(size: 28, weight: .semibold))
                Text("The attention surface for agents")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 48)

            HStack(spacing: 16) {
                HomeCard(
                    title: "New Agent Session",
                    subtitle: "claude · codex · grok — detected on PATH",
                    primary: true,
                    action: { appState.showNewSession = true }
                )
                HomeCard(
                    title: "Plain Terminal",
                    subtitle: "shell in any directory",
                    primary: false,
                    action: { newPlainTerminal() }
                )
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let primary: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 15, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering
                          ? Color(nsColor: .controlColor)
                          : Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(primary ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: primary ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
