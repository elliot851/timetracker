import Foundation

struct Shift: Codable, Identifiable {
    let id: UUID
    let start: Date
    var end: Date?

    init(start: Date = Date()) {
        self.id = UUID()
        self.start = start
        self.end = nil
    }

    var isActive: Bool { end == nil }

    /// Counts up live while the shift is still open.
    var duration: TimeInterval { (end ?? Date()).timeIntervalSince(start) }
}

/// Owns the shift history and persists it as JSON next to the screenshots.
final class ShiftStore {
    static let shared = ShiftStore()

    static let didChange = Notification.Name("ShiftStoreDidChange")

    private(set) var shifts: [Shift] = []

    /// Always the logged-in user's file; recording follows whoever is current.
    private var fileURL: URL {
        AccountStore.shared.userDir(AccountStore.shared.current.id)
            .appendingPathComponent("shifts.json")
    }

    private init() {
        load()
    }

    /// Re-read after the logged-in user changes (dev switcher / future login).
    func reloadForCurrentUser() {
        load()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Read-only load of another user's shifts, for admin views of their data.
    static func shifts(for userId: String) -> [Shift] {
        let file = AccountStore.shared.userDir(userId).appendingPathComponent("shifts.json")
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Shift].self, from: data)) ?? []
    }

    /// Whether another user is currently clocked in, read from their file.
    static func activeShift(for userId: String) -> Shift? {
        shifts(for: userId).last { $0.isActive }
    }

    static func total(on date: Date, shifts: [Shift]) -> TimeInterval {
        let calendar = Calendar.current
        return shifts
            .filter { calendar.isDate($0.start, inSameDayAs: date) }
            .reduce(0) { $0 + $1.duration }
    }

    var active: Shift? {
        shifts.last(where: { $0.isActive })
    }

    var isClockedIn: Bool { active != nil }

    @discardableResult
    func clockIn() -> Shift? {
        guard !isClockedIn else { return nil }
        let shift = Shift()
        shifts.append(shift)
        persist()
        return shift
    }

    /// `at` lets idle handling close the shift when the user stopped working, not when they answered.
    @discardableResult
    func clockOut(at date: Date = Date()) -> Shift? {
        guard let index = shifts.lastIndex(where: { $0.isActive }) else { return nil }
        shifts[index].end = max(date, shifts[index].start)
        persist()
        return shifts[index]
    }

    func shifts(on date: Date) -> [Shift] {
        let calendar = Calendar.current
        return shifts.filter { calendar.isDate($0.start, inSameDayAs: date) }
    }

    func total(on date: Date) -> TimeInterval {
        shifts(on: date).reduce(0) { $0 + $1.duration }
    }

    /// Sum of every shift in the same calendar week as `date` (Monday-based).
    func total(inWeekOf date: Date) -> TimeInterval {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return shifts
            .filter { week.contains($0.start) }
            .reduce(0) { $0 + $1.duration }
    }

    // MARK: - Persistence

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(shifts).write(to: fileURL)
        } catch {
            NSLog("Could not save shifts: %@", error.localizedDescription)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        Sync.pushShifts()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        shifts = (try? decoder.decode([Shift].self, from: data)) ?? []
    }
}

enum Format {
    /// 02:14:09 — for the live clock.
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// 2h 14m — for summaries.
    static func compact(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
