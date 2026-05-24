import Foundation

struct StreakEngine: Sendable {

    // MARK: - Logical Day

    /// Dates between midnight and 3 AM belong to the previous calendar day.
    static func logicalDay(for date: Date = Date()) -> (year: Int, month: Int, day: Int) {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let adjusted = hour < 3
            ? cal.date(byAdding: .day, value: -1, to: date) ?? date
            : date
        let c = cal.dateComponents([.year, .month, .day], from: adjusted)
        return (c.year!, c.month!, c.day!)
    }

    // MARK: - Streak Calculation

    static func calculateStreak(from days: [ReadingDay], minReads: Int = 1) -> (current: Int, longest: Int) {
        let active = days.filter { $0.linksRead >= minReads }
        guard !active.isEmpty else { return (0, 0) }

        let sorted = active.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year > rhs.year }
            if lhs.month != rhs.month { return lhs.month > rhs.month }
            return lhs.day > rhs.day
        }

        let today = logicalDay()
        let yesterday = offsetDay(today, by: -1)

        // A streak is live if we read today or read yesterday (today still counts).
        let topTuple = (sorted[0].year, sorted[0].month, sorted[0].day)
        let todayTuple = (today.year, today.month, today.day)
        let yestTuple = (yesterday.year, yesterday.month, yesterday.day)

        guard topTuple == todayTuple || topTuple == yestTuple else {
            return (0, longestRun(sorted))
        }

        var current = 0
        var prev: (year: Int, month: Int, day: Int)? = nil
        for entry in sorted {
            let cur = (entry.year, entry.month, entry.day)
            if let p = prev {
                let expected = offsetDay(p, by: -1)
                guard (cur.0, cur.1, cur.2) == (expected.year, expected.month, expected.day) else { break }
            }
            current += 1
            prev = cur
        }

        return (current, max(current, longestRun(sorted)))
    }

    static func hasReadToday(days: [ReadingDay], minReads: Int = 1) -> Bool {
        let t = logicalDay()
        return days.contains { $0.year == t.year && $0.month == t.month && $0.day == t.day && $0.linksRead >= minReads }
    }

    /// True when the user hasn't met the daily minimum today and has an active streak to protect.
    static func isStreakAtRisk(days: [ReadingDay], minReads: Int = 1) -> Bool {
        guard !hasReadToday(days: days, minReads: minReads) else { return false }
        let streak = calculateStreak(from: days, minReads: minReads)
        return streak.current > 0
    }

    // MARK: - Recent Activity

    /// Returns `count` booleans oldest-first (index 0 = `count-1` days ago, last = today).
    /// `true` means the user read at least one link that logical day.
    static func recentActivity(days: [ReadingDay], count: Int, minReads: Int = 1) -> [Bool] {
        let today = logicalDay()
        return (0..<count).map { offset in
            let target = offsetDay(today, by: -(count - 1 - offset))
            return days.contains {
                $0.year == target.year && $0.month == target.month && $0.day == target.day && $0.linksRead >= minReads
            }
        }
    }

    // MARK: - Helpers

    private static func offsetDay(_ d: (year: Int, month: Int, day: Int), by offset: Int) -> (year: Int, month: Int, day: Int) {
        var comps = DateComponents()
        comps.year = d.year; comps.month = d.month; comps.day = d.day
        let cal = Calendar.current
        guard let date = cal.date(from: comps),
              let shifted = cal.date(byAdding: .day, value: offset, to: date)
        else { return d }
        let sc = cal.dateComponents([.year, .month, .day], from: shifted)
        return (sc.year!, sc.month!, sc.day!)
    }

    private static func longestRun(_ sorted: [ReadingDay]) -> Int {
        var longest = 0
        var run = 0
        var prev: (year: Int, month: Int, day: Int)? = nil
        for entry in sorted {
            let cur = (entry.year, entry.month, entry.day)
            if let p = prev {
                let expected = offsetDay(p, by: -1)
                if (cur.0, cur.1, cur.2) == (expected.year, expected.month, expected.day) {
                    run += 1
                } else {
                    longest = max(longest, run)
                    run = 1
                }
            } else {
                run = 1
            }
            prev = cur
        }
        return max(longest, run)
    }
}
