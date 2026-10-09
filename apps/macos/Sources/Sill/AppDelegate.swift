import AppKit
import SwiftUI

/// Window lifecycle, app-wide key commands, layout restore/save, and the
/// blocked→composer focus jump (J2). Chrome stays out of the PTY hot path —
/// every handler here is cheap bookkeeping on events the surfaces emit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var window: NSWindow!
    nonisolated(unsafe) private var keyMonitor: Any?
    nonisolated(unsafe) private var blockedObserver: NSObjectProtocol?
    nonisolated(unsafe) private var newTerminalObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sill"
        // contentMinSize (not minSize) so the floor is on the drawable area,
        // matching ContentView's own 560×400 frame minimum — titlebar
        // height stays out of the arithmetic.
        window.contentMinSize = NSSize(width: 560, height: 400)
        // Dark-first chrome: sheets, alerts, menus and the title bar inherit
        // the app appearance, not the system one.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedRed: 0x0C / 255.0, green: 0x0C / 255.0, blue: 0x0E / 255.0, alpha: 1)
        window.titlebarSeparatorStyle = .none
        window.center()
        window.contentView = NSHostingView(rootView: ContentView(appState: appState))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(.regular)

        buildMenus()
        installKeyMonitor()
        restoreLayout()
        Notifier.requestAuth()

        blockedObserver = NotificationCenter.default.addObserver(
            forName: .sillPaneBlocked, object: nil, queue: .main
        ) { [weak self] note in
            guard let pane = note.object as? Pane else { return }
            // Ring + unread handled by the model. A blocked pane that isn't
            // focused shows its rail ring only — Cmd+' is the jump — so the
            // composer-focus event only fires for the focused pane.
            if self?.window.isKeyWindow != true {
                if let p = pane.status.isBlocked ? pane : nil {
                    Notifier.post(title: "Sill — \(p.title)",
                                  body: p.status.railLabel)
                }
            } else if self?.appState.focusedId == pane.id {
                NotificationCenter.default.post(name: .sillFocusComposer, object: pane)
            }
        }
        newTerminalObserver = NotificationCenter.default.addObserver(
            forName: .sillNewTerminal, object: nil, queue: .main
        ) { [weak self] _ in self?.newPlainTerminal() }

        // Window title + dock badge track the focused pane and blocked count.
        appState.onChromeChange = { [weak self] in self?.updateChrome() }

        // `sill state` fallback path: hooks write pane-<id>.json files under
        // ~/.config/sill/state/; a light poll applies them to the rail.
        statePollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in self?.pollStateFiles()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        LayoutStore.save(appState: appState)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Layout restore (FR-011)

    private func restoreLayout() {
        guard let layout = LayoutStore.load(), !layout.panes.isEmpty else { return }
        for saved in layout.panes {
            let cwd = saved.cwd.isEmpty
                ? FileManager.default.homeDirectoryForCurrentUser
                : URL(fileURLWithPath: saved.cwd)
            let argv = saved.launch.isEmpty
                ? [ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh", "-l"]
                : saved.launch
            let pane = Pane(title: saved.title ?? argv.first ?? "Terminal",
                            cwd: cwd, argv: argv,
                            agent: saved.agent, sessionId: saved.session)
            // Resume uses the pane's own launch argv — the official CLI
            // resume flags were baked in at save time. Failure → error strip
            // on the pane, session id kept.
            pane.viewMode = ViewMode(rawValue: saved.viewMode) ?? .raw
            pane.composerDraft = saved.composerDraft
            appState.addPane(pane)
            pane.surface = SwiftTermSurface(pane: pane, appState: appState)
            try? pane.surface?.spawn()
        }
        // Restore the saved focus; addPane's last-wins default otherwise.
        if let savedFocus = layout.focused,
           let match = appState.panes.first(where: { $0.id.uuidString == savedFocus }) {
            appState.focusedId = match.id
        }
        appState.terminalMode = layout.terminalMode
        appState.showHome = appState.panes.isEmpty
    }

    // MARK: - sill state file watch (adapter fallback, FR-008)

    private var statePollTimer: Timer?

    /// Window title mirrors the focused pane; the dock badge counts panes
    /// awaiting input — both cheap enough to also run on the 1s poll so
    /// drift from @Published pane-internal changes gets caught.
    private func updateChrome() {
        window?.title = appState.focused.map { "\($0.title) — Sill" } ?? "Sill"
        let blocked = appState.panes.count { $0.status.isBlocked }
        NSApp.dockTile.badgeLabel = blocked > 0 ? "\(blocked)" : nil
    }

    private func pollStateFiles() {
        let dir = LayoutStore.configDir.appendingPathComponent("state")
        for pane in appState.panes {
            let url = dir.appendingPathComponent("pane-\(pane.id.uuidString).json")
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ts = (obj["ts_ms"] as? NSNumber)?.doubleValue, ts > pane.lastHookTs else { continue }
            pane.lastHookTs = ts
            applyHookEvent(pane: pane, obj: obj)
        }
        // After applying this tick's events so a cleared block clears the
        // badge in the same tick rather than lingering one poll behind.
        updateChrome()
    }

    private func applyHookEvent(pane: Pane, obj: [String: Any]) {
        if let session = obj["session"] as? String, !session.isEmpty {
            pane.sessionId = session
        }
        let agent = obj["agent"] as? String
        let state = ((obj["record"] as? [String: Any])?["state"] as? String) ?? (obj["state"] as? String)
        let kind = obj["kind"] as? String
        let msg = obj["msg"] as? String
        switch state {
        case "blocked":
            pane.record(.status, "awaiting\(kind.map { " · \($0)" } ?? "")\(agent.map { " · \($0)" } ?? "")")
            appState.markBlocked(pane, kind: kind)
        case "error": pane.status = .error
        case "done": pane.status = .done; pane.unread = pane.unread || appState.focusedId != pane.id
        case "working": pane.status = .working
        case "idle": pane.status = .idle
        case "clear": pane.status = .idle
        default: return // null/unknown = liveness only
        }
        if let msg, !msg.isEmpty { pane.record(.status, msg) }
        appState.refreshChrome()
    }

    private func newPlainTerminal() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let pane = Pane(title: "Terminal", cwd: home, argv: [shell, "-l"])
        appState.addPane(pane)
        pane.surface = SwiftTermSurface(pane: pane, appState: appState)
        try? pane.surface?.spawn()
    }

    // MARK: - Menus (PRD §7: New / Close / Preferences / Toggle Terminal Mode)

    private func buildMenus() {
        let main = NSMenu()
        let appMenu = NSMenuItem()
        appMenu.submenu = NSMenu(title: "Sill")
        appMenu.submenu?.addItem(withTitle: "About Sill", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.submenu?.addItem(.separator())
        appMenu.submenu?.addItem(withTitle: "Quit Sill", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appMenu)

        let file = NSMenuItem()
        file.submenu = NSMenu(title: "File")
        file.submenu?.addItem(withTitle: "New Session", action: #selector(newSession), keyEquivalent: "n")
        file.submenu?.addItem(withTitle: "New Terminal", action: #selector(newTerminal), keyEquivalent: "t")
        file.submenu?.addItem(.separator())
        file.submenu?.addItem(withTitle: "Close Pane", action: #selector(closePane), keyEquivalent: "w")
        main.addItem(file)

        // Standard Edit menu — without it Cmd+V/C/X/A are dead app-wide.
        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: "Edit")
        edit.submenu?.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.submenu?.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.submenu?.addItem(.separator())
        edit.submenu?.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.submenu?.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.submenu?.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.submenu?.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(edit)

        let view = NSMenuItem()
        view.submenu = NSMenu(title: "View")
        view.submenu?.addItem(withTitle: "Command Palette", action: #selector(palette), keyEquivalent: "P")
        view.submenu?.addItem(withTitle: "Toggle Rail", action: #selector(toggleRail), keyEquivalent: "b")
        view.submenu?.addItem(withTitle: "Toggle Terminal Mode", action: #selector(terminalMode), keyEquivalent: "")
        view.submenu?.addItem(withTitle: "Jump to Unread Blocked", action: #selector(jumpUnread), keyEquivalent: "'")
        main.addItem(view)

        NSApp.mainMenu = main
    }

    @objc private func newSession() { appState.showNewSession = true }
    @objc private func newTerminal() { newPlainTerminal() }
    @objc private func closePane() { if let p = appState.focused { appState.closePane(p) } }
    @objc private func palette() { appState.showPalette = true }
    @objc private func terminalMode() { appState.terminalMode.toggle() }
    @objc private func toggleRail() { appState.railCollapsed.toggle() }
    @objc private func jumpUnread() { appState.jumpToOldestBlocked() }

    // MARK: - Key commands

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self, ev.modifierFlags.contains(.command) else { return ev }
            switch ev.charactersIgnoringModifiers ?? "" {
            case "'":
                if self.appState.jumpToOldestBlocked() {
                    NotificationCenter.default.post(name: .sillFocusComposer, object: self.appState.focused)
                    return nil
                }
                return ev
            case "1"..."9":
                if let digit = Int(ev.charactersIgnoringModifiers ?? ""),
                   digit <= self.appState.panes.count {
                    let pane = self.appState.panes[digit - 1]
                    self.appState.focusedId = pane.id
                    pane.unread = false
                    return nil
                }
                return ev
            default:
                return ev
            }
        }
    }

    // Observers and the key monitor are process-lifetime by design — the
    // AppDelegate outlives every window, so no deinit teardown is needed.
}
