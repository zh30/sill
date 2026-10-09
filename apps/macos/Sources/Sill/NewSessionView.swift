import AppKit
import SwiftUI

/// New Agent Session flow (J1): providers detected on PATH, a custom command
/// fallback, and a directory picker. A provider missing from PATH produces a
/// card-local error + install hint — never a fake pane (PRD §11).
struct NewSessionView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var customCommand = ""
    @State private var directory: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Agent Session")
                .font(.system(size: 15, weight: .semibold))

            VStack(spacing: 8) {
                ForEach(Providers.catalog) { p in
                    ProviderRow(provider: p) { launch(provider: p) }
                }
                HStack(spacing: 8) {
                    Text("▣").frame(width: 14)
                    TextField("Custom command…", text: $customCommand)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { if !customCommand.isEmpty { launch(custom: customCommand) } }
                }
            }

            HStack(spacing: 8) {
                Text("Directory").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(directory.path).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { chooseDirectory() }
            }

            if let launchError {
                // Card-local error + hint — no phantom session (FR-004).
                Text(launchError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            directory = url
        }
    }

    private func launch(provider: Provider) {
        guard provider.available else {
            launchError = "\(provider.executable) is not on PATH — install \(provider.name) first."
            return
        }
        launchError = nil
        spawnPane(title: provider.name, argv: provider.launchArgs, agent: provider.id)
    }

    private func launch(custom command: String) {
        let argv = command.split(separator: " ").map(String.init)
        guard let exe = argv.first, Providers.which(exe) || exe.hasPrefix("/") else {
            launchError = "\(argv.first ?? command) is not on PATH."
            return
        }
        launchError = nil
        spawnPane(title: argv.first!, argv: argv, agent: nil)
    }

    private func spawnPane(title: String, argv: [String], agent: String?) {
        let pane = Pane(title: title, cwd: directory, argv: argv, agent: agent)
        appState.addPane(pane)
        pane.surface = SwiftTermSurface(pane: pane, appState: appState)
        try? pane.surface?.spawn()
        dismiss()
    }
}

/// One row: provider glyph + name, dimmed when absent from PATH.
struct ProviderRow: View {
    let provider: Provider
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(glyph).frame(width: 14)
                Text(provider.name).font(.system(size: 13))
                Spacer()
                if !provider.available {
                    Text("not on PATH")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(provider.available ? 1 : 0.55)
    }

    private var glyph: String {
        switch provider.id {
        case "claude": return "◐"
        case "codex": return "◆"
        case "grok": return "▲"
        default: return "▣"
        }
    }
}


