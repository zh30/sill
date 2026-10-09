import Foundation

/// OSC events consumed by the chrome. Mirrors `core/sill-core/src/osc.rs` —
/// this is a second consumer of the *public* OSC 7501 contract (the protocol,
/// not the parser, is the product surface).
enum OscEvent {
    case status(state: String, id: String?, app: String?, kind: String?, msg: String?)
    case commandMark(mark: Character, exitCode: Int?)
    case cwd(String)
    case link(String)
    case notify(body: String, source: String)
    case progress(state: Int, percent: Int?)
    case clipboardWrite
}

/// Streaming scanner — a read-only tee on the PTY byte stream. Nothing is
/// consumed or rewritten; unknown OSC and unknown keys are ignored.
final class OscScanner {
    private var buf = Data()
    private var inSeq = false
    private let maxSeq = 64 * 1024

    func feed(_ data: Data) -> [OscEvent] {
        var out: [OscEvent] = []
        var i = 0
        let bytes = [UInt8](data)
        while i < bytes.count {
            if !inSeq {
                if bytes[i] == 0x1b, i + 1 < bytes.count, bytes[i + 1] == 0x5d {
                    inSeq = true
                    buf.removeAll(keepingCapacity: true)
                    i += 2
                    continue
                }
                if bytes[i] == 0x9d {
                    inSeq = true
                    buf.removeAll(keepingCapacity: true)
                    i += 1
                    continue
                }
                i += 1
            } else {
                let b = bytes[i]
                if b == 0x07 {
                    finish(&out)
                    i += 1
                } else if b == 0x1b {
                    if i + 1 < bytes.count, bytes[i + 1] == 0x5c {
                        finish(&out)
                        i += 2
                    } else if i + 1 == bytes.count {
                        buf.append(b)
                        i += 1
                    } else {
                        abandon()
                    }
                } else {
                    if buf.last == 0x1b, b == 0x5c {
                        buf.removeLast()
                        finish(&out)
                        i += 1
                        continue
                    }
                    buf.append(b)
                    i += 1
                    if buf.count > maxSeq { abandon() }
                }
            }
        }
        return out
    }

    private func finish(_ out: inout [OscEvent]) {
        let payload = buf
        buf.removeAll(keepingCapacity: true)
        inSeq = false
        if let ev = Self.parse(payload) { out.append(ev) }
    }

    private func abandon() {
        buf.removeAll(keepingCapacity: true)
        inSeq = false
    }

    private static func parse(_ payload: Data) -> OscEvent? {
        guard let text = String(data: payload, encoding: .utf8) else { return nil }
        let parts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        let code = String(parts[0])
        let rest = parts.count > 1 ? String(parts[1]) : ""
        switch code {
        case "7501": return parse7501(rest)
        case "133": return parse133(rest)
        case "7": return .cwd(decodeFileURL(rest))
        case "8":
            guard let uri = rest.split(separator: ";").last, !uri.isEmpty else { return nil }
            return .link(String(uri))
        case "9":
            if rest.hasPrefix("4;") {
                let f = String(rest.dropFirst(2)).split(separator: ";")
                guard let st = f.first.flatMap({ Int($0) }) else { return nil }
                let pct = f.count > 1 ? Int(f[1]) : nil
                return .progress(state: st, percent: pct)
            }
            return .notify(body: rest, source: "osc9")
        case "99", "777":
            let body = String(rest.split(separator: ";").last ?? "")
            return .notify(body: body, source: "osc\(code)")
        case "52": return .clipboardWrite
        default: return nil
        }
    }

    private static func parse7501(_ rest: String) -> OscEvent? {
        var state: String?
        var id: String?
        var app: String?
        var kind: String?
        var msg: String?
        for pair in rest.split(separator: ":") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let k = String(pair[..<eq])
            let v = String(pair[pair.index(after: eq)...])
            switch k {
            case "state": state = v
            case "id": id = v
            case "app": app = v
            case "kind": kind = ["permission", "question", "auth"].contains(v) ? v : nil
            case "msg":
                if let d = Data(base64Encoded: v), let s = String(data: d, encoding: .utf8) {
                    msg = s
                }
            default: break // unknown key — ignored
            }
        }
        guard let s = state,
              ["idle", "working", "done", "blocked", "error", "clear"].contains(s) else {
            return nil // `state` required — drop the whole sequence
        }
        return .status(state: s, id: id, app: app, kind: kind, msg: msg)
    }

    private static func parse133(_ rest: String) -> OscEvent? {
        let mark = rest.first
        switch mark {
        case "A", "B", "C":
            return .commandMark(mark: mark!, exitCode: nil)
        case "D":
            var code: Int?
            for kv in rest.dropFirst(2).split(separator: ";") {
                if let v = kv.split(separator: "=").last, kv.hasPrefix("exitcode") {
                    code = Int(v)
                }
            }
            return .commandMark(mark: "D", exitCode: code)
        default: return nil
        }
    }

    private static func decodeFileURL(_ url: String) -> String {
        var path = url
        if url.hasPrefix("file://"), let slash = url.dropFirst(7).firstIndex(of: "/") {
            path = String(url[slash...])
        }
        return path.removingPercentEncoding ?? path
    }
}
