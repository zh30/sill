import AppKit
import Foundation
import UserNotifications

/// System notifications — only when the window is not visible (FR-016),
/// remote OSC notifications off by default (FR-013). Fails soft: an ad-hoc
/// build without a proper bundle id may be denied authorization; the rail +
/// ring still carry the state.
enum Notifier {
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    static func post(title: String, body: String) {
        // Default policy: only when the app window isn't the key window.
        guard NSApp.keyWindow == nil || !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content,
                                        trigger: nil)
        center.add(req)
    }
}
