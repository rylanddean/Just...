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
