import SwiftData
import Foundation

@Model
final class ReadingDay {
    var id: UUID = UUID()
    var year: Int = 0
    var month: Int = 0
    var day: Int = 0   // logical day — 3AM grace window applied at write time
    var linksRead: Int = 0

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}
