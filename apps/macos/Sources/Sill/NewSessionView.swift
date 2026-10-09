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
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Agent Session")
                .font(T.ui(15, .semibold))
                .foregroundStyle(T.fg)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "PROVIDERS")
                VStack(spacing: 6) {
                    ForEach(Providers.catalog) { p in
                        ProviderRow(provider: p) { launch(provider: p) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "CUSTOM COMMAND")
                HStack(spacing: 10) {
                    GlyphTile(agent: nil, size: 22)
                    TextField("command + args…", text: $customCommand)
                        .textFieldStyle(.plain)
                        .font(T.mono(12))
                        .foregroundStyle(T.fg)
                        .focused($customFocused)
                        .onSubmit { if !customCommand.isEmpty { launch(custom: customCommand) } }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(T.raised)
                // Focus ring matches the field, not the keyboard: the accent
                // border is the same signal the blocked ring uses elsewhere.
                .overlay(
                    RoundedRectangle(cornerRadius: T.radiusSm)
                        .stroke(customFocused ? T.accent.opacity(0.6) : T.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: T.radiusSm))
            }

            HStack(spacing: 8) {
                Text("Directory").font(T.ui(11)).foregroundStyle(T.subtle)
                Text(directory.path).font(T.mono(11)).foregroundStyle(T.fg.opacity(0.8))
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { chooseDirectory() }
                    .buttonStyle(SillButtonStyle())
            }

            if let launchError {
                // Card-local error + hint — no phantom session (FR-004).
                // Chip-styled so it reads as UI, not a stray red string.
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(T.ui(10))
                        .foregroundStyle(T.error)
                    Text(launchError)
                        .font(T.mono(10))
                        .foregroundStyle(T.error.opacity(0.9))
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(T.error.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: T.radiusSm).stroke(T.error.opacity(0.3), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: T.radiusSm))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SillButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(T.bg)
        .onAppear { customFocused = true }
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
            launchError = "\(provider.executable) is not on PATH — install with:\n\(provider.installHint)"
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

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GlyphTile(agent: provider.id, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.name).font(T.ui(12, .medium)).foregroundStyle(T.fg)
                    Text(provider.executable).font(T.mono(10)).foregroundStyle(T.faint)
                }
                Spacer()
                if !provider.available {
                    Text("not on PATH")
                        .font(T.ui(10))
                        .foregroundStyle(T.faint)
                } else if hovering {
                    Text("launch →")
                        .font(T.ui(10))
                        .foregroundStyle(T.subtle)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(hovering ? T.rowHover : T.raised)
            .overlay(RoundedRectangle(cornerRadius: T.radiusSm).stroke(T.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: T.radiusSm))
            .contentShape(Rectangle())
        }
        .buttonStyle(SillCardStyle())
        .opacity(provider.available ? 1 : 0.5)
        .onHover { hovering = $0 }
    }
}


