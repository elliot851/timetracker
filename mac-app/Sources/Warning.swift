import Foundation

/// A recorded inactivity event: who, when, the evidence screenshot, and what they
/// chose to do about it. Admins review these; the user sees their own.
struct WarningRecord: Codable {
    enum Outcome: String, Codable {
        case resumed
        case clockedOut

        var label: String { self == .resumed ? "Went back to work" : "Clocked out" }
    }

    let id: String
    let userId: String
    let userName: String
    /// When activity actually stopped, not when the dialog appeared.
    let startedAt: Date
    var resolvedAt: Date?
    var outcome: Outcome?
    /// Relative to the user's screenshots folder, e.g. "2026-09-15/2026-09-15_14-02-11.jpg".
    let screenshot: String?
    let activity: Int
    let app: String?

    /// How long the paused, uncounted stretch lasted.
    var pausedSeconds: TimeInterval { (resolvedAt ?? Date()).timeIntervalSince(startedAt) }
}

enum WarningStore {
    static let didChange = Notification.Name("WarningStoreDidChange")

    private static func file(for userId: String) -> URL {
        AccountStore.shared.userDir(userId).appendingPathComponent("warnings.json")
    }

    static func all(for userId: String) -> [WarningRecord] {
        guard let data = try? Data(contentsOf: file(for: userId)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WarningRecord].self, from: data)) ?? []
    }

    /// Every user's warnings, newest first — the admin view.
    static func allUsers() -> [WarningRecord] {
        AccountStore.shared.allUsers()
            .flatMap { all(for: $0.id) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func append(_ record: WarningRecord) {
        var records = all(for: record.userId)
        records.append(record)
        save(records, for: record.userId)
        Sync.pushWarning(record)

        // Admins are the audience for these; the person themselves already sees the dialog.
        if AccountStore.shared.isAdmin {
            Notifier.post(
                title: "Idle: \(record.userName)",
                body: "No activity since \(Format.time.string(from: record.startedAt)). "
                    + "The timer is paused.")
        }
    }

    static func update(_ record: WarningRecord) {
        var records = all(for: record.userId)
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
        save(records, for: record.userId)
        Sync.pushWarning(record)
    }

    static func screenshotURL(for record: WarningRecord) -> URL? {
        guard let path = record.screenshot else { return nil }
        return Storage.screenshotsDir(user: record.userId).appendingPathComponent(path)
    }

    private static func save(_ records: [WarningRecord], for userId: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = file(for: userId)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(records).write(to: url)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
