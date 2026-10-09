import Foundation

/// Agent providers detected on PATH (J1 step 3: 有什么列什么).
struct Provider: Identifiable {
    let id: String
    let name: String
    let executable: String
    let available: Bool
    /// Template argv for a fresh session.
    let launchArgs: [String]
}

enum Providers {
    static let catalog: [Provider] = [
        Provider(id: "claude", name: "Claude Code", executable: "claude",
                 available: which("claude"), launchArgs: ["claude"]),
        Provider(id: "codex", name: "Codex CLI", executable: "codex",
                 available: which("codex"), launchArgs: ["codex"]),
        Provider(id: "grok", name: "Grok CLI", executable: "grok",
                 available: which("grok"), launchArgs: ["grok"]),
    ]

    static func which(_ name: String) -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"]
            ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        return path.split(separator: ":").contains { dir in
            FileManager.default.isExecutableFile(atPath: "\(dir)/\(name)")
        }
    }

    static var detected: [Provider] { catalog.filter(\.available) }

    static func paneTitle(for agent: String?) -> String {
        guard let agent else { return "Terminal" }
        return catalog.first { $0.id == agent }?.name ?? agent
    }
}
