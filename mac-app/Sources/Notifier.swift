import Foundation
import UserNotifications

/// Delivers warnings to whoever is supposed to act on them. Local notifications for
/// now; the same call site will push to admins once the backend exists.
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    Log.write("Notification permission denied: \(error.localizedDescription)")
                } else {
                    Log.write("Notification permission: \(granted)")
                }
            }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Tracks which warnings the person at this machine has already seen, so the
/// sidebar can show an unread count.
enum WarningInbox {
    private static let key = "seenWarningIds"

    static func relevantWarnings() -> [WarningRecord] {
        let account = AccountStore.shared
        return account.isAdmin
            ? WarningStore.allUsers()
            : WarningStore.all(for: account.current.id).sorted { $0.startedAt > $1.startedAt }
    }

    static func unreadCount() -> Int {
        let seen = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        return relevantWarnings().filter { !seen.contains($0.id) }.count
    }

    static func markAllRead() {
        let ids = relevantWarnings().map(\.id)
        UserDefaults.standard.set(ids, forKey: key)
    }
}
