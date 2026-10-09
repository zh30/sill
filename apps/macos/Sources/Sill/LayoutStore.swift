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
        var composerDraft = ""
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
            // Agent panes resume through the official CLI flag — `launch` is
            // the resume command, not the original argv (FR-011).
            out += "launch = [\(resumeArgv(agent: p.agent, session: p.sessionId, fallback: p.argv).map(tomlString).joined(separator: ", "))]\n"
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
        // Drafts may hold unsent secrets — keep layout files user-only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: configDir.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lastLayoutURL.path)
    }

    /// Official resume argv per provider (mirrors sill-core
    /// `agent_resume_argv`). Unknown agents keep the pane's own launch.
    private static func resumeArgv(agent: String?, session: String?, fallback: [String]) -> [String] {
        guard let a = agent, let s = session, !s.isEmpty else { return fallback }
        switch a {
        case "claude": return ["claude", "--resume", s]
        case "codex": return ["codex", "resume", s]
        case "grok": return ["grok", "--resume", s]
        default: return fallback
        }
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
        var out = "\""
        for c in s {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if c.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
                    for u in c.unicodeScalars { out += String(format: "\\u%04X", u.value) }
                } else {
                    out.append(c)
                }
            }
        }
        return out + "\""
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
            case "composer_draft": current!.composerDraft = val
            default: break
            }
        }
        flush()
        layout.panes.sort { $0.railOrder < $1.railOrder }
        return layout
    }

    private static func unquote(_ s: String) -> String {
        var v = s
        guard v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 else { return v }
        v = String(v.dropFirst().dropLast())
        var out = ""
        var i = v.startIndex
        while i < v.endIndex {
            if v[i] == "\\", let next = v.index(i, offsetBy: 1, limitedBy: v.endIndex), next < v.endIndex {
                switch v[next] {
                case "n": out += "\n"
                case "r": out += "\r"
                case "t": out += "\t"
                case "\\": out += "\\"
                case "\"": out += "\""
                case "u":
                    let h0 = v.index(i, offsetBy: 2)
                    let h1 = v.index(i, offsetBy: 6, limitedBy: v.endIndex) ?? v.endIndex
                    if v.distance(from: h0, to: h1) == 4, let cp = UInt32(v[h0..<h1], radix: 16), let sc = Unicode.Scalar(cp) {
                        out += String(Character(sc))
                        i = h1
                        continue
                    }
                    out += "\\u"
                default: out += String(v[next])
                }
                i = v.index(next, offsetBy: 1)
            } else {
                out.append(v[i])
                i = v.index(after: i)
            }
        }
        return out
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
