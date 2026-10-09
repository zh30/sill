import AppKit
import Combine
import Foundation

/// The shared five-point pane status (protocols/osc-7501.md).
enum PaneStatus: Equatable {
    case unknown // no 7501, no hook — never guessed
    case idle
    case working
    case done
    case blocked(kind: String?) // kind: permission | question | auth | nil
    case error

    var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }

    var railLabel: String {
        switch self {
        case .unknown: return "unknown"
        case .idle: return "idle"
        case .working: return "processing"
        case .done: return "done"
        case .blocked(let kind): return kind.map { "awaiting · \($0)" } ?? "awaiting"
        case .error: return "error"
        }
    }
}

enum ViewMode: String {
    case raw, transcript
}

/// One pane = one PTY surface + rail row + composer draft.
/// Main-actor bound: all mutations come from UI/main-queue callbacks.
@MainActor
final class Pane: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String
    @Published var cwd: URL
    @Published var argv: [String]
    @Published var agent: String? // adapter id: claude|codex|grok|nil
    @Published var sessionId: String?
    @Published var status: PaneStatus = .unknown
    @Published var unread = false
    @Published var viewMode: ViewMode = .raw
    @Published var altScreen = false // forces Raw + locks the toggle (FR-006)
    @Published var cwdSubline: String = ""
    @Published var transcript: [TranscriptEvent] = []
    @Published var processAlive = false
    @Published var spawnError: String?
    @Published var composerDraft = ""
    var surface: (any SillSurface)?

    struct TranscriptEvent: Identifiable {
        let id = UUID()
        let ts = Date()
        let text: String
        let kind: Kind
        enum Kind { case status, command, cwd, notify, progress }
    }

    init(title: String, cwd: URL, argv: [String], agent: String? = nil, sessionId: String? = nil) {
        self.title = title
        self.cwd = cwd
        self.argv = argv
        self.agent = agent
        self.sessionId = sessionId
        self.cwdSubline = cwd.lastPathComponent
    }

    func record(_ ev: TranscriptEvent.Kind, _ text: String) {
        transcript.append(TranscriptEvent(text: text, kind: ev))
        if transcript.count > 2000 { transcript.removeFirst(transcript.count - 2000) }
    }
}

/// App-wide workspace state — the single source for chrome + layout save.
@MainActor
final class AppState: ObservableObject {
    @Published var panes: [Pane] = []
    @Published var focusedId: Pane.ID?
    @Published var railCollapsed = false
    @Published var terminalMode = false
    @Published var showHome = true
    @Published var showPalette = false
    @Published var showNewSession = false

    var focused: Pane? { panes.first { $0.id == focusedId } }

    @discardableResult
    func addPane(_ pane: Pane) -> Pane {
        panes.append(pane)
        focusedId = pane.id
        showHome = false
        return pane
    }

    func closePane(_ pane: Pane) {
        pane.surface?.terminate()
        panes.removeAll { $0.id == pane.id }
        if focusedId == pane.id { focusedId = panes.last?.id }
        if panes.isEmpty { showHome = true }
    }

    /// `Cmd+'` — jump to the oldest unread blocked pane (FR-005).
    @discardableResult
    func jumpToOldestBlocked() -> Bool {
        guard let target = panes.first(where: { $0.status.isBlocked && $0.unread })
            ?? panes.first(where: { $0.status.isBlocked }) else { return false }
        focusedId = target.id
        showHome = false
        target.unread = false
        return true
    }

    func markBlocked(_ pane: Pane, kind: String?) {
        let wasFocused = focusedId == pane.id
        pane.status = .blocked(kind: kind)
        if !wasFocused { pane.unread = true }
        NotificationCenter.default.post(name: .sillPaneBlocked, object: pane)
    }

    /// When a blocked pane is visible and focused, input belongs in the
    /// composer (J2 ends there). Clearing unread happens on focus anyway.
    func focusComposerIfNeeded(_ pane: Pane) {
        if pane.status.isBlocked && focusedId == pane.id {
            NotificationCenter.default.post(name: .sillFocusComposer, object: pane)
        }
    }
}

extension Notification.Name {
    static let sillPaneBlocked = Notification.Name("sill.paneBlocked")
    static let sillFocusComposer = Notification.Name("sill.focusComposer")
    static let sillEscapeToPty = Notification.Name("sill.escapeToPty")
    static let sillNewTerminal = Notification.Name("sill.newTerminal")
}
