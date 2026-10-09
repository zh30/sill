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
            HStack(spacing: 8) {
                Text("⌘").font(T.mono(13)).foregroundStyle(T.faint)
                TextField("jump to command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(T.ui(13))
                    .foregroundStyle(T.fg)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            Divider().overlay(T.borderSoft)
            List(filtered) { cmd in
                Text(cmd.title)
                    .font(T.ui(12))
                    .foregroundStyle(T.fg.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
                    .listRowInsets(EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismiss()
                        cmd.run(appState)
                    }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(CGFloat(filtered.count) * 30, 280))
        }
        .frame(width: 400)
        .background(T.surface)
        .overlay(RoundedRectangle(cornerRadius: T.radiusMd).stroke(T.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: T.radiusMd))
    }
}

extension AppState {
    func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: self)
    }
}
