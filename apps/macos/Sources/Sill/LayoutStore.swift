import Foundation

/// Reads/writes `~/.config/sill/last-layout.toml` — version-1 schema in
/// docs/layout.md. The write side emits exactly that schema; the reader is a
/// tolerant mini-parser for the same shape (unknown keys ignored). The Rust
/// `sill-core` layout module is the canonical implementation — this exists so
/// the app stays self-contained until the FFI seam is wired.
enum LayoutStore {
    struct SavedPane {
        var id = ""
        var title: String?
        var cwd = ""
        var launch: [String] = []
        var agent: String?
        var session: String?
        var viewMode = "raw"
        var railOrder = 0
    }

    static var configDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        return (xdg.map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".config"))
            .appendingPathComponent("sill")
    }

    static var lastLayoutURL: URL { configDir.appendingPathComponent("last-layout.toml") }

    // MARK: - write

    @MainActor
    static func save(appState: AppState) {
        var out = "version = 1\n\n[workspace]\n"
        if let f = appState.focusedId {
            out += "focused = \"\(f.uuidString)\"\n"
        }
        out += "terminal_mode = \(appState.terminalMode)\n"
        for (order, p) in appState.panes.enumerated() {
            out += "\n[[pane]]\n"
            out += "id = \"\(p.id.uuidString)\"\n"
            out += "title = \(tomlString(p.title))\n"
            out += "cwd = \(tomlString(p.cwd.path))\n"
            out += "launch = [\(p.argv.map(tomlString).joined(separator: ", "))]\n"
            if let a = p.agent { out += "agent = \(tomlString(a))\n" }
            if let s = p.sessionId { out += "session = \(tomlString(s))\n" }
            out += "view_mode = \"\(p.viewMode.rawValue)\"\n"
            out += "rail_order = \(order)\n"
            out += "composer_pinned = false\n"
            let draft = String(p.composerDraft.prefix(200 * 1024))
            if !draft.isEmpty { out += "composer_draft = \(tomlString(draft))\n" }
            out += "\n[pane.status]\n"
            out += "state = \"\(statusWire(p.status))\"\n"
        }
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try? out.write(to: lastLayoutURL, atomically: true, encoding: .utf8)
    }

    private static func statusWire(_ s: PaneStatus) -> String {
        switch s {
        case .idle: return "idle"
        case .working: return "working"
        case .done: return "done"
        case .blocked: return "blocked"
        case .error: return "error"
        case .unknown: return "unknown"
        }
    }

    private static func tomlString(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    // MARK: - read

    struct SavedLayout {
        var focused: String?
        var terminalMode = false
        var panes: [SavedPane] = []
    }

    static func load() -> SavedLayout? {
        guard let text = try? String(contentsOf: lastLayoutURL, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Tolerant parser for exactly the schema `save` emits + the documented
    /// fields. Unknown keys/sections are ignored (forward-compatible).
    static func parse(_ text: String) -> SavedLayout {
        var layout = SavedLayout()
        var current: SavedPane?
        var inWorkspace = false
        var inStatus = false

        func flush() {
            if let p = current { layout.panes.append(p) }
            current = nil
        }

        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line == "[workspace]" { flush(); inWorkspace = true; inStatus = false; continue }
            if line == "[[pane]]" { flush(); inWorkspace = false; inStatus = false; current = SavedPane(); continue }
            if line == "[pane.status]" { inStatus = true; inWorkspace = false; continue }
            if line.hasPrefix("[") { inWorkspace = false; inStatus = false; continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let rawVal = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let val = unquote(rawVal)

            if inWorkspace {
                if key == "focused" { layout.focused = val }
                if key == "terminal_mode" { layout.terminalMode = rawVal == "true" }
                continue
            }
            guard !inStatus, current != nil else { continue }
            switch key {
            case "id": current!.id = val
            case "title": current!.title = val
            case "cwd": current!.cwd = val
            case "launch": current!.launch = parseStringArray(rawVal)
            case "agent": current!.agent = val
            case "session": current!.session = val
            case "view_mode": current!.viewMode = val
            case "rail_order": current!.railOrder = Int(rawVal) ?? 0
            default: break
            }
        }
        flush()
        layout.panes.sort { $0.railOrder < $1.railOrder }
        return layout
    }

    private static func unquote(_ s: String) -> String {
        var v = s
        if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 {
            v = String(v.dropFirst().dropLast())
            v = v.replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return v
    }

    private static func parseStringArray(_ s: String) -> [String] {
        guard s.hasPrefix("["), s.hasSuffix("]") else { return [] }
        let inner = s.dropFirst().dropLast()
        var out: [String] = []
        var cur = ""
        var inStr = false
        var esc = false
        for ch in inner {
            if esc { cur.append(ch); esc = false; continue }
            if ch == "\\" { esc = true; continue }
            if ch == "\"" {
                if inStr { out.append(cur); cur = ""; inStr = false } else { inStr = true }
                continue
            }
            if inStr { cur.append(ch) }
        }
        return out
    }
}
