import Foundation

/// Aggregations over the recorded data. Everything the Analytics page shows is
/// derived here so the view stays presentation-only.
enum Analytics {
    enum Period: Int, CaseIterable {
        case today, week, month

        var label: String {
            switch self {
            case .today: return "Today"
            case .week: return "7 days"
            case .month: return "30 days"
            }
        }

        var days: Int {
            switch self {
            case .today: return 1
            case .week: return 7
            case .month: return 30
            }
        }
    }

    struct AppTotal {
        let name: String
        let seconds: Int
    }

    struct PersonStats {
        let user: UserProfile
        let worked: TimeInterval
        let activity: Int?
        let warnings: Int
        let isWorkingNow: Bool
    }

    struct HourBucket {
        let hour: Int
        let minutes: Int
        let activity: Int?
    }

    struct DayPoint {
        let date: Date
        let minutes: Int
        let activity: Int?
    }

    /// How the tracked minutes split by how busy they were — the classification ring.
    struct Classification {
        let core: Int        // >= 66%
        let light: Int       // 33-65%
        let idle: Int        // < 33%
        var total: Int { core + light + idle }
    }

    /// The days covered by a period, newest first.
    static func dates(for period: Period) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<period.days).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private static func records(for users: [UserProfile], dates: [Date]) -> [MinuteRecord] {
        users.flatMap { user in
            dates.flatMap { DayData.minutes(on: $0, user: user.id) }
        }
    }

    // MARK: - Headline numbers

    static func totalWorked(_ users: [UserProfile], dates: [Date]) -> TimeInterval {
        users.reduce(0) { sum, user in
            sum + dates.reduce(0) { $0 + DayData.totalWorked(on: $1, user: user.id) }
        }
    }

    static func averageActivity(_ users: [UserProfile], dates: [Date]) -> Int? {
        let values = records(for: users, dates: dates).map(\.overall)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    static func warningCount(_ users: [UserProfile], dates: [Date]) -> Int {
        guard let earliest = dates.min() else { return 0 }
        let calendar = Calendar.current
        let cutoff = calendar.startOfDay(for: earliest)
        return users.reduce(0) { sum, user in
            sum + WarningStore.all(for: user.id).filter { $0.startedAt >= cutoff }.count
        }
    }

    static func workingNow(_ users: [UserProfile]) -> [UserProfile] {
        users.filter { user in
            if user.id == AccountStore.shared.current.id { return ShiftStore.shared.isClockedIn }
            return ShiftStore.activeShift(for: user.id) != nil
        }
    }

    // MARK: - Breakdowns

    /// Seconds spent per application, busiest first.
    static func topApps(_ users: [UserProfile], dates: [Date], limit: Int = 8) -> [AppTotal] {
        var totals: [String: Int] = [:]
        for record in records(for: users, dates: dates) {
            for slice in record.apps {
                totals[slice.name, default: 0] += slice.seconds
            }
        }
        return totals
            .map { AppTotal(name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(limit)
            .map { $0 }
    }

    /// Tracked minutes and average activity per hour of the day.
    static func hourly(_ users: [UserProfile], dates: [Date]) -> [HourBucket] {
        let calendar = Calendar.current
        var counts: [Int: Int] = [:]
        var sums: [Int: Int] = [:]
        for record in records(for: users, dates: dates) {
            let hour = calendar.component(.hour, from: record.timestamp)
            counts[hour, default: 0] += 1
            sums[hour, default: 0] += record.overall
        }
        guard let first = counts.keys.min(), let last = counts.keys.max() else { return [] }
        return (first...last).map { hour in
            let count = counts[hour] ?? 0
            return HourBucket(
                hour: hour,
                minutes: count,
                activity: count > 0 ? (sums[hour] ?? 0) / count : nil)
        }
    }

    /// Minutes tracked per day across the period, oldest first — the trend sparkline.
    static func daily(_ users: [UserProfile], dates: [Date]) -> [DayPoint] {
        dates.sorted().map { date in
            let recs = records(for: users, dates: [date])
            let activity = recs.isEmpty ? nil : recs.map(\.overall).reduce(0, +) / recs.count
            return DayPoint(date: date, minutes: recs.count, activity: activity)
        }
    }

    static func classification(_ users: [UserProfile], dates: [Date]) -> Classification {
        var core = 0, light = 0, idle = 0
        for record in records(for: users, dates: dates) {
            switch record.overall {
            case 66...: core += 1
            case 33..<66: light += 1
            default: idle += 1
            }
        }
        return Classification(core: core, light: light, idle: idle)
    }

    /// A tiny recent-days activity series for a single person, for the row sparkline.
    static func sparkline(for userId: String, days: Int = 7) -> [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset -> Int? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let recs = DayData.minutes(on: date, user: userId)
            return recs.isEmpty ? 0 : recs.map(\.overall).reduce(0, +) / recs.count
        }
    }

    static func perPerson(_ users: [UserProfile], dates: [Date]) -> [PersonStats] {
        let active = Set(workingNow(users).map(\.id))
        return users.map { user in
            PersonStats(
                user: user,
                worked: dates.reduce(0) { $0 + DayData.totalWorked(on: $1, user: user.id) },
                activity: averageActivity([user], dates: dates),
                warnings: warningCount([user], dates: dates),
                isWorkingNow: active.contains(user.id))
        }
        .sorted { $0.worked > $1.worked }
    }
}
