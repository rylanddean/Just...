import SwiftData
import Foundation

@Model
final class ReadingDay {
    var id: UUID = UUID()
    var year: Int
    var month: Int
    var day: Int       // logical day — 3AM grace window applied at write time
    var linksRead: Int = 0

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}
