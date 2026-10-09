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
            // Ring + unread handled by the model. Notification only when the
            // window isn't visible; then focus jumps to the composer.
            if self?.window.isKeyWindow != true {
                if let p = pane.status.isBlocked ? pane : nil {
                    Notifier.post(title: "Sill — \(p.title)",
                                  body: p.status.railLabel)
                }
            } else {
                NotificationCenter.default.post(name: .sillFocusComposer, object: pane)
            }
        }
        newTerminalObserver = NotificationCenter.default.addObserver(
            forName: .sillNewTerminal, object: nil, queue: .main
        ) { [weak self] _ in self?.newPlainTerminal() }
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
            appState.addPane(pane)
            pane.surface = SwiftTermSurface(pane: pane, appState: appState)
            try? pane.surface?.spawn()
        }
        appState.terminalMode = layout.terminalMode
        appState.showHome = appState.panes.isEmpty
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

        let view = NSMenuItem()
        view.submenu = NSMenu(title: "View")
        view.submenu?.addItem(withTitle: "Command Palette", action: #selector(palette), keyEquivalent: "P")
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
