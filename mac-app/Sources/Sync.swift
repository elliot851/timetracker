import Foundation

/// Pushes locally recorded data to the server so the website mirrors the app.
/// Everything stays on disk too; sync is best-effort and retries screenshots that
/// fail (e.g. before R2 is enabled).
enum Sync {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The R2 key for a screenshot: "<day>/<filename>".
    static func key(for filename: String, on date: Date) -> String {
        "\(dayFormatter.string(from: date))/\(filename)"
    }

    // MARK: - Push

    static func pushShifts() {
        let shifts = ShiftStore.shared.shifts.map { shift -> [String: Any] in
            var row: [String: Any] = ["id": shift.id.uuidString, "start": iso.string(from: shift.start)]
            if let end = shift.end { row["end"] = iso.string(from: end) }
            return row
        }
        guard !shifts.isEmpty else { return }
        Task { await APIClient.sendJSON("/api/shifts", shifts) }
    }

    static func pushMinute(_ record: MinuteRecord) {
        let keys = record.screenshots.map { key(for: $0, on: record.timestamp) }
        let apps = record.apps.map { slice -> [String: Any] in
            var a: [String: Any] = ["name": slice.name, "seconds": slice.seconds]
            if let title = slice.title { a["title"] = title }
            return a
        }
        let row: [String: Any] = [
            "ts": iso.string(from: record.timestamp),
            "keyboard": record.keyboard, "mouse": record.mouse, "overall": record.overall,
            "apps": apps, "screenshots": keys,
        ]
        Task { await APIClient.sendJSON("/api/minutes", [row]) }
    }

    static func pushWarning(_ w: WarningRecord) {
        var body: [String: Any] = [
            "id": w.id, "startedAt": iso.string(from: w.startedAt), "activity": w.activity,
        ]
        if let r = w.resolvedAt { body["resolvedAt"] = iso.string(from: r) }
        if let o = w.outcome { body["outcome"] = o.rawValue }
        if let s = w.screenshot { body["screenshot"] = s }   // already "day/filename"
        if let a = w.app { body["app"] = a }
        Task { await APIClient.sendJSON("/api/warnings", body) }
    }

    /// Uploads the given screenshot files. Silent no-op if R2 isn't ready yet.
    static func uploadScreenshots(_ urls: [URL], on date: Date) {
        for url in urls {
            let k = key(for: url.lastPathComponent, on: date)
            Task {
                guard let data = try? Data(contentsOf: url) else { return }
                await APIClient.uploadShot(key: k, data: data)
            }
        }
    }
}
