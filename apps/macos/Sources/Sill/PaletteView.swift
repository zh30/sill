import SwiftUI

/// Palette (V7, FR-015): Cmd+Shift+P command runner over the P0 verbs.
struct PaletteView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    struct Command: Identifiable {
        let id = UUID()
        let title: String
        let run: (AppState) -> Void
    }

    private var commands: [Command] {
        [
            Command(title: "New Agent Session") { $0.showNewSession = true },
            Command(title: "New Terminal") { st in st.post(.sillNewTerminal) },
            Command(title: "Toggle Raw / Transcript") { st in
                guard let p = st.focused, !p.altScreen else { return }
                p.viewMode = p.viewMode == .raw ? .transcript : .raw
            },
            Command(title: "Toggle Rail") { $0.railCollapsed.toggle() },
            Command(title: "Terminal Mode") { $0.terminalMode.toggle() },
            Command(title: "Jump to Unread Blocked") { _ = $0.jumpToOldestBlocked() },
            Command(title: "Import Ghostty Config") { _ in
                // Report lives in the CLI (`sill import ghostty`); deep-link
                // into it so the surface stays a thin mirror.
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["-a", "Terminal", "sill import ghostty"]
                try? task.run()
            },
            Command(title: "Export Layout") { _ in
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["-a", "Terminal", "sill export layout"]
                try? task.run()
            },
            Command(title: "Close Pane") { st in
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
            TextField("Command…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(10)
            Divider()
            List(filtered) { cmd in
                Text(cmd.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismiss()
                        cmd.run(appState)
                    }
            }
            .listStyle(.plain)
            .frame(height: min(CGFloat(filtered.count) * 28, 260))
        }
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

extension AppState {
    func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: self)
    }
}
