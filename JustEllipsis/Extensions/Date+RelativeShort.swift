import Foundation

extension Date {
    /// Relative string capped at days/hours/minutes — never shows seconds.
    var relativeShort: String {
        let seconds = Int(max(0, Date().timeIntervalSince(self)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr ago" }
        let days = hours / 24
        return "\(days) \(days == 1 ? "day" : "days") ago"
    }
}
