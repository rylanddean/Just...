import Foundation

struct NightModeService {
    static let startHourKey   = "nightMode.startHour"
    static let startMinuteKey = "nightMode.startMinute"
    static let overrideKey    = "nightMode.override"

    static let defaultStartHour   = 21  // 9 pm
    static let defaultStartMinute = 0

    static func isActive(hour: Int, minute: Int, override: String) -> Bool {
        switch override {
        case "on":  return true
        case "off": return false
        default:    return isScheduledNow(startHour: hour, startMinute: minute)
        }
    }

    // Night runs from startHour:startMinute until 6am, crossing midnight.
    private static func isScheduledNow(startHour: Int, startMinute: Int) -> Bool {
        let comps     = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMins   = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let startMins = startHour * 60 + startMinute
        let endMins   = 6 * 60
        return startMins > endMins
            ? nowMins >= startMins || nowMins < endMins
            : nowMins >= startMins && nowMins < endMins
    }
}
