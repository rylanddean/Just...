import Testing
import Foundation
@testable import JustEllipsis

@Suite("StreakEngine")
struct StreakEngineTests {

    // MARK: - Logical Day

    @Test("Midnight-to-3AM belongs to previous calendar day")
    func logicalDayGraceWindow() {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 2
        comps.minute = 30
        let twoThirtyAM = Calendar.current.date(from: comps)!

        let logical = StreakEngine.logicalDay(for: twoThirtyAM)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yComps = Calendar.current.dateComponents([.year, .month, .day], from: yesterday)

        #expect(logical.year  == yComps.year)
        #expect(logical.month == yComps.month)
        #expect(logical.day   == yComps.day)
    }

    @Test("3AM and later belongs to current calendar day")
    func logicalDayAfterGrace() {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 3
        comps.minute = 0
        let threeAM = Calendar.current.date(from: comps)!

        let logical = StreakEngine.logicalDay(for: threeAM)
        let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())

        #expect(logical.year  == today.year)
        #expect(logical.month == today.month)
        #expect(logical.day   == today.day)
    }

    // MARK: - Streak Calculation

    @Test("Empty reading days returns zero streak")
    func emptyDays() {
        let result = StreakEngine.calculateStreak(from: [])
        #expect(result.current == 0)
        #expect(result.longest == 0)
    }

    @Test("Single reading today produces streak of 1")
    func singleDayToday() {
        let t = StreakEngine.logicalDay()
        let day = ReadingDay(year: t.year, month: t.month, day: t.day)
        day.linksRead = 1
        let result = StreakEngine.calculateStreak(from: [day])
        #expect(result.current == 1)
        #expect(result.longest == 1)
    }

    @Test("Gap breaks streak")
    func gapBreaksStreak() throws {
        // Build two consecutive days, skip one, then today
        let today = StreakEngine.logicalDay()
        let cal = Calendar.current

        func makeDay(offsetFromToday: Int, links: Int) -> ReadingDay {
            guard let date = cal.date(byAdding: .day, value: offsetFromToday, to: Date()) else {
                fatalError()
            }
            let c = cal.dateComponents([.year, .month, .day], from: date)
            let d = ReadingDay(year: c.year!, month: c.month!, day: c.day!)
            d.linksRead = links
            return d
        }

        let days = [
            makeDay(offsetFromToday:  0, links: 1),
            makeDay(offsetFromToday: -1, links: 1),
            // gap at -2
            makeDay(offsetFromToday: -3, links: 1),
            makeDay(offsetFromToday: -4, links: 1),
        ]

        let result = StreakEngine.calculateStreak(from: days)
        #expect(result.current == 2)
        #expect(result.longest == 2)
    }

    // MARK: - Recent Activity

    func makeDay(daysAgo: Int, links: Int = 1) -> ReadingDay {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let d = ReadingDay(year: c.year!, month: c.month!, day: c.day!)
        d.linksRead = links
        return d
    }

    @Test("Empty days returns all false")
    func recentActivityEmpty() {
        let result = StreakEngine.recentActivity(days: [], count: 7)
        #expect(result == Array(repeating: false, count: 7))
    }

    @Test("Today read sets last element true, rest false")
    func recentActivityTodayOnly() {
        let result = StreakEngine.recentActivity(days: [makeDay(daysAgo: 0)], count: 7)
        #expect(result.last == true)
        #expect(result.dropLast().allSatisfy { !$0 })
    }

    @Test("Full week returns all true")
    func recentActivityFullWeek() {
        let days = (0..<7).map { makeDay(daysAgo: $0) }
        #expect(StreakEngine.recentActivity(days: days, count: 7) == Array(repeating: true, count: 7))
    }

    @Test("Partial week maps to correct positions")
    func recentActivityPartialWeek() {
        // today (daysAgo=0) → index 6, two days ago (daysAgo=2) → index 4
        let days = [makeDay(daysAgo: 0), makeDay(daysAgo: 2)]
        let result = StreakEngine.recentActivity(days: days, count: 7)
        #expect(result[6] == true)
        #expect(result[4] == true)
        #expect(result[5] == false)
        #expect(result[3] == false)
    }

    @Test("Days outside the window are excluded")
    func recentActivityOldDayIgnored() {
        let days = [makeDay(daysAgo: 7), makeDay(daysAgo: 10)]
        let result = StreakEngine.recentActivity(days: days, count: 7)
        #expect(result == Array(repeating: false, count: 7))
    }

    @Test("Logical day used — entry for logical today at index count-1")
    func recentActivityUsesLogicalDay() {
        let today = StreakEngine.logicalDay()
        let d = ReadingDay(year: today.year, month: today.month, day: today.day)
        d.linksRead = 3
        let result = StreakEngine.recentActivity(days: [d], count: 7)
        #expect(result[6] == true)
    }

    // MARK: - minReads threshold

    @Test("Day with fewer reads than minReads does not count")
    func minReadsThresholdMiss() {
        let day = makeDay(daysAgo: 0, links: 1)
        let result = StreakEngine.recentActivity(days: [day], count: 7, minReads: 2)
        #expect(result[6] == false)
    }

    @Test("Day meeting minReads exactly counts")
    func minReadsThresholdExact() {
        let day = makeDay(daysAgo: 0, links: 3)
        let result = StreakEngine.recentActivity(days: [day], count: 7, minReads: 3)
        #expect(result[6] == true)
    }

    @Test("Streak breaks when minReads not met")
    func minReadsBreaksStreak() {
        // today and yesterday each have only 1 read; require 2
        let days = [makeDay(daysAgo: 0, links: 1), makeDay(daysAgo: 1, links: 1)]
        let result = StreakEngine.calculateStreak(from: days, minReads: 2)
        #expect(result.current == 0)
    }

    @Test("Streak counts when minReads met")
    func minReadsBuildsStreak() {
        let days = [makeDay(daysAgo: 0, links: 2), makeDay(daysAgo: 1, links: 3)]
        let result = StreakEngine.calculateStreak(from: days, minReads: 2)
        #expect(result.current == 2)
    }

    @Test("isStreakAtRisk respects minReads")
    func minReadsAtRisk() {
        // read today but only 1 link; require 2 — not at risk because today counts, streak is alive
        // Actually: hasReadToday with minReads=2 returns false → check if at risk
        let today = makeDay(daysAgo: 0, links: 1)
        let yesterday = makeDay(daysAgo: 1, links: 2)
        // streak is 1 (yesterday met threshold), today hasn't met it yet
        #expect(StreakEngine.isStreakAtRisk(days: [today, yesterday], minReads: 2) == true)
    }

    // MARK: - At Risk

    @Test("hasReadToday is false when no entry for today")
    func hasReadTodayFalse() {
        #expect(StreakEngine.hasReadToday(days: []) == false)
    }

    @Test("hasReadToday is true when today has linksRead > 0")
    func hasReadTodayTrue() {
        let t = StreakEngine.logicalDay()
        let day = ReadingDay(year: t.year, month: t.month, day: t.day)
        day.linksRead = 2
        #expect(StreakEngine.hasReadToday(days: [day]) == true)
    }
}
