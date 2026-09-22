import Foundation

/// Where each user's data lives on disk and how screenshots are named.
///
/// Layout: `~/Documents/TimeTracker/users/<id>/screenshots/2026-09-11/2026-09-11_19-09-17.jpg`
/// The timestamp prefix makes Finder's name sort chronological. Recording always
/// targets the logged-in user; reads may target any user (admins browse others).
enum Storage {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    /// The user data is being written for (the one clocked in on this machine).
    static var recordingUserId: String { AccountStore.shared.current.id }

    static func screenshotsDir(user id: String) -> URL {
        AccountStore.shared.userDir(id).appendingPathComponent("screenshots", isDirectory: true)
    }

    static func activityDir(user id: String) -> URL {
        AccountStore.shared.userDir(id).appendingPathComponent("activity", isDirectory: true)
    }

    static func logFile(user id: String) -> URL {
        AccountStore.shared.userDir(id).appendingPathComponent("tracker.log")
    }

    static func dayFolder(for date: Date, user id: String) -> URL {
        screenshotsDir(user: id).appendingPathComponent(
            dayFormatter.string(from: date), isDirectory: true)
    }

    static func destination(for date: Date, display: Int, of total: Int) throws -> URL {
        let folder = dayFolder(for: date, user: recordingUserId)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = stampFormatter.string(from: date)
        let name = total > 1 ? "\(stamp)_display\(display).jpg" : "\(stamp).jpg"
        return folder.appendingPathComponent(name)
    }

    /// One JSON line per minute in `activity/2026-09-11.jsonl` — the record that
    /// will later be uploaded alongside the screenshots it names.
    static func appendMinute(_ record: MinuteRecord) {
        let folder = activityDir(user: recordingUserId)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(
            dayFormatter.string(from: record.timestamp) + ".jsonl")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(record) else { return }
        data.append(0x0A)

        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }

    static func countToday(user id: String = recordingUserId) -> Int {
        let folder = dayFolder(for: Date(), user: id)
        let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        return files?.filter { $0.hasSuffix(".jpg") }.count ?? 0
    }
}
