import AppKit

/// One captured minute: its activity, how many screenshots it holds, and a thumbnail.
struct GalleryMinute {
    let date: Date
    let activity: Int
    let keyboard: Int
    let mouse: Int
    let screenshots: [URL]
    let app: String?

    var thumbURL: URL? { screenshots.first }
    var shotCount: Int { screenshots.count }
}

/// A clock hour's worth of minutes, plus how many minutes were actually worked in it.
struct HourGroup {
    let start: Date
    let minutes: [GalleryMinute]
    var workedMinutes: Int { minutes.count }
}

/// Reads a day's minute records and groups them by hour for the Hubstaff-style gallery.
enum DayData {
    static func minutes(on date: Date, user id: String) -> [MinuteRecord] {
        let day = DateFormatter.day.string(from: date)
        let file = Storage.activityDir(user: id).appendingPathComponent("\(day).jsonl")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(MinuteRecord.self, from: data)
        }
    }

    static func hours(on date: Date, user id: String) -> [HourGroup] {
        let folder = Storage.dayFolder(for: date, user: id)
        let calendar = Calendar.current

        var buckets: [Date: [GalleryMinute]] = [:]
        for record in minutes(on: date, user: id) {
            let hour = calendar.dateInterval(of: .hour, for: record.timestamp)?.start
                ?? record.timestamp
            let urls = record.screenshots.map { folder.appendingPathComponent($0) }
            buckets[hour, default: []].append(GalleryMinute(
                date: record.timestamp,
                activity: record.overall,
                keyboard: record.keyboard,
                mouse: record.mouse,
                screenshots: urls,
                app: record.apps.first?.name))
        }

        return buckets
            .map { HourGroup(start: $0.key, minutes: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.start > $1.start }
    }

    static func averageActivity(on date: Date, user id: String) -> Int? {
        let overalls = minutes(on: date, user: id).map(\.overall)
        guard !overalls.isEmpty else { return nil }
        return overalls.reduce(0, +) / overalls.count
    }

    /// Total worked that day for a given user, read from their shifts file.
    static func totalWorked(on date: Date, user id: String) -> TimeInterval {
        ShiftStore.total(on: date, shifts: ShiftStore.shifts(for: id))
    }
}

extension DateFormatter {
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum ActivityColor {
    static func of(_ percent: Int) -> NSColor {
        switch percent {
        case 66...: return NSColor(srgbRed: 0.298, green: 0.733, blue: 0.365, alpha: 1)
        case 33..<66: return NSColor(srgbRed: 0.953, green: 0.663, blue: 0.216, alpha: 1)
        default: return Palette.danger
        }
    }
}
