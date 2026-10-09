import AppKit
import Foundation
import SwiftTerm
import SwiftUI

/// The seam every terminal backend implements (docs/architecture.md).
/// `SwiftTermSurface` is the dev backend; `LibghosttySurface` binds the
/// vendored core through this same protocol — chrome code never differs.
@MainActor
protocol SillSurface: AnyObject {
    var view: NSView { get }
    func spawn() throws
    /// Composer → PTY. Callers wrap in bracketed paste themselves.
    func write(_ data: Data)
    func focusPty()
    var isAltScreen: Bool { get }
    func terminate()
}

/// TerminalView subclass so we can observe the alt-buffer switch
/// (`bufferActivated` is open on TerminalView; the terminal arrives as `source`).
final class SillTerminalView: LocalProcessTerminalView {
    var onBufferActivated: ((Bool) -> Void)?

    override func bufferActivated(source: Terminal) {
        super.bufferActivated(source: source)
        onBufferActivated?(source.isCurrentBufferAlternate)
    }
}

@MainActor
final class SwiftTermSurface: NSObject, SillSurface, LocalProcessTerminalViewDelegate {
    let terminalView = SillTerminalView(frame: .zero)
    var view: NSView { terminalView }

    private let pane: Pane
    private weak var appState: AppState?
    private var oscObservation: TerminalOscObservation?

    var isAltScreen: Bool { pane.altScreen }

    init(pane: Pane, appState: AppState) {
        self.pane = pane
        self.appState = appState
        super.init()

        let tv = terminalView
        tv.processDelegate = self
        tv.font = Self.terminalFont()
        tv.optionAsMetaKey = true
        tv.nativeForegroundColor = NSColor.textColor
        tv.nativeBackgroundColor = NSColor.textBackgroundColor
        tv.onBufferActivated = { [weak pane] alt in
            Task { @MainActor in
                pane?.altScreen = alt
                if alt { pane?.viewMode = .raw } // TUI forces Raw (FR-006)
            }
        }
        oscObservation = tv.observeOscEvents { [weak self] event in
            Task { @MainActor in self?.handleOsc(event) }
        }
    }

    private static func terminalFont() -> NSFont {
        NSFont(name: "JetBrains Mono", size: 13)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    func spawn() throws {
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        let pe = ProcessInfo.processInfo.environment
        env.append("TERM_PROGRAM=sill")
        env.append("TERM_PROGRAM_VERSION=0.1.0")
        env.append("SILL_PANE=\(pane.id.uuidString)")
        if let shell = pe["SHELL"] { env.append("SHELL=\(shell)") }
        env.append("PATH=\(pe["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")")
        if let lang = pe["LANG"] { env.append("LANG=\(lang)") }

        guard let exe = pane.argv.first, !exe.isEmpty else {
            pane.spawnError = "empty launch command"
            return
        }
        terminalView.startProcess(
            executable: exe,
            args: Array(pane.argv.dropFirst()),
            environment: env,
            currentDirectory: pane.cwd.path
        )
        pane.processAlive = true
    }

    func write(_ data: Data) {
        terminalView.send(source: terminalView, data: ArraySlice([UInt8](data)))
    }

    /// Composer send: bracketed paste per FR-007.
    func writePasted(_ text: String) {
        var bytes: [UInt8] = [0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e] // CSI 200~
        bytes.append(contentsOf: [UInt8](text.utf8))
        bytes.append(contentsOf: [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e]) // CSI 201~
        terminalView.send(source: terminalView, data: ArraySlice(bytes))
    }

    func focusPty() {
        terminalView.window?.makeFirstResponder(terminalView)
    }

    func terminate() {
        terminalView.terminate()
    }

    // MARK: - OSC routing (133 marks, notify, links — 7501 comes via the delegate)

    private func handleOsc(_ event: TerminalOscEvent) {
        let pane = self.pane
        let payload = String(decoding: event.payload, as: UTF8.self)
        switch event.code {
        case 133:
            let mark = payload.first ?? "?"
            if mark == "D" {
                var code: Int?
                for kv in payload.dropFirst(2).split(separator: ";") where kv.hasPrefix("exitcode=") {
                    code = Int(kv.dropFirst(9))
                }
                pane.record(.command, "command finished\(code.map { " (exit \($0))" } ?? "")")
            } else if mark == "C" {
                pane.record(.command, "command started")
            }
        case 9, 99, 777:
            let body = String(payload.split(separator: ";").last ?? "")
            if !body.isEmpty {
                // OSC notify lands in the transcript only. System
                // notifications for remote writers are default-off (FR-013);
                // a local-only opt-in lands with config.
                pane.record(.notify, body)
            }
        case 8:
            if let uri = payload.split(separator: ";").last, !uri.isEmpty {
                pane.record(.notify, "link: \(uri)")
            }
        default:
            break
        }
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func scrolled(source: TerminalView, position: Double) {}
    func bell(source: TerminalView) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let dir = directory, !dir.isEmpty else { return }
        let path = Self.decodeFileURL(dir)
        Task { @MainActor in
            self.pane.cwd = URL(fileURLWithPath: path)
            self.pane.cwdSubline = URL(fileURLWithPath: path).lastPathComponent
            self.pane.record(.cwd, path)
        }
    }

    /// OSC 7 arrives as `file://host/path` — strip scheme+host and
    /// percent-decode before it ever becomes a filesystem path.
    static func decodeFileURL(_ raw: String) -> String {
        guard raw.hasPrefix("file://") else { return raw }
        let rest = String(raw.dropFirst(7))
        guard let slash = rest.firstIndex(of: "/") else { return raw }
        var path = String(rest[slash...])
        // percent-decode (utf8-safe enough for paths)
        var out = ""
        var i = path.startIndex
        while i < path.endIndex {
            if path[i] == "%",
               let h = path.index(i, offsetBy: 3, limitedBy: path.endIndex), h <= path.endIndex,
               let byte = UInt8(path[path.index(after: i)..<h], radix: 16) {
                out.append(Character(Unicode.Scalar(byte)))
                i = h
            } else {
                out.append(path[i])
                i = path.index(after: i)
            }
        }
        path = out
        return path
    }

    func programStatusChanged(source: TerminalView, records: [TerminalProgramStatus]) {
        Task { @MainActor in
            self.applyStatus(records)
        }
    }

    @MainActor
    private func applyStatus(_ records: [TerminalProgramStatus]) {
        // Effective badge = highest-priority live record (mirrors sill-core
        // StatusStore.effective): blocked > error > done > working > idle.
        let best = records.max { lhs, rhs in
            priority(lhs.state) < priority(rhs.state)
        }
        let newStatus: PaneStatus
        switch best?.state {
        case .blocked: newStatus = .blocked(kind: best?.kind?.rawValue)
        case .error: newStatus = .error
        case .done: newStatus = .done
        case .working: newStatus = .working
        case .idle: newStatus = .idle
        case nil: newStatus = pane.status == .unknown ? .unknown : .idle
        }
        let label = newStatus.railLabel
        pane.record(.status, "\(label)\(best?.effectiveApp.map { " · \($0)" } ?? "")")

        if newStatus.isBlocked {
            appState?.markBlocked(pane, kind: best?.kind?.rawValue)
        } else {
            pane.status = newStatus
        }
    }

    private func priority(_ s: TerminalProgramStatusState) -> Int {
        switch s {
        case .blocked: return 5
        case .error: return 4
        case .done: return 3
        case .working: return 2
        case .idle: return 1
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.pane.processAlive = false
            let note = "process exited\(exitCode.map { " (\($0))" } ?? "")"
            self.pane.exited = true
            self.pane.exitNote = note
            self.pane.record(.status, note)
            if self.pane.status == .unknown { self.pane.status = .idle }
        }
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        Task { @MainActor in
            self.pane.processAlive = false
            self.pane.spawnError = "failed to launch \(self.pane.argv.first ?? ""): \(error)"
        }
    }

    /// OSC 8 links: every open is confirmed — a remote writer could emit
    /// `file:` or any other scheme (FR-009, FR-013).
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link) else { return }
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "Open link?"
            alert.informativeText = link
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// OSC 52 clipboard write: default off (FR-013). Keep it that way.
    func clipboardCopy(source: TerminalView, content: Data) {}
    func clipboardRead(source: TerminalView) -> Data? { nil }
}

/// Thin NSViewRepresentable wrapper — the surface lives on the Pane so
/// switching Raw/Transcript keeps the PTY + view alive underneath.
struct SurfaceNSView: NSViewRepresentable {
    let surface: any SillSurface

    func makeNSView(context: Context) -> NSView { surface.view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
