import Foundation
import UserNotifications
import SwiftData

struct NotificationScheduler {

    // MARK: - AppStorage Keys

    static let morningEnabledKey  = "notifications.morning.enabled"
    static let morningHourKey     = "notifications.morning.hour"
    static let morningMinuteKey   = "notifications.morning.minute"
    static let eveningEnabledKey  = "notifications.evening.enabled"
    static let eveningHourKey     = "notifications.evening.hour"
    static let eveningMinuteKey   = "notifications.evening.minute"

    // MARK: - Defaults

    static let defaultMorningHour   = 8
    static let defaultMorningMinute = 0
    static let defaultEveningHour   = 20
    static let defaultEveningMinute = 0

    // MARK: - Notification IDs

    static let editionEnabledKey = "notifications.edition.enabled"

    private static let morningID    = "je.notification.morning"
    private static let eveningID    = "je.notification.evening"
    private static let streakLostID = "je.notification.streakLost"
    private static let editionID    = "je.notification.edition"

    // MARK: - Permission

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Reschedule

    /// Cancels all pending notifications and re-schedules based on current app state.
    /// Call every time the app becomes active.
    static func reschedule(
        queueCount: Int,
        readingDays: [ReadingDay],
        minReads: Int,
        morningEnabled: Bool,
        morningHour: Int,
        morningMinute: Int,
        eveningEnabled: Bool,
        eveningHour: Int,
        eveningMinute: Int
    ) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningID, eveningID, streakLostID])

        let hasReadToday = StreakEngine.hasReadToday(days: readingDays, minReads: minReads)
        let streak = StreakEngine.calculateStreak(from: readingDays, minReads: minReads).current

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let cal = Calendar.current
            let nowHour   = cal.component(.hour,   from: Date())
            let nowMinute = cal.component(.minute, from: Date())

            // Morning queue nudge — only fires if the scheduled time is still ahead today
            if morningEnabled, queueCount > 0, !hasReadToday {
                let alreadyPast = nowHour > morningHour || (nowHour == morningHour && nowMinute >= morningMinute)
                if !alreadyPast {
                    let s = queueCount == 1 ? "" : "s"
                    scheduleToday(id: morningID,
                                  body: "You have \(queueCount) link\(s) waiting.",
                                  hour: morningHour,
                                  minute: morningMinute)
                }
            }

            // Evening streak-at-risk — only fires if time is still ahead today
            if eveningEnabled, streak > 0, !hasReadToday {
                let alreadyPast = nowHour > eveningHour || (nowHour == eveningHour && nowMinute >= eveningMinute)
                if !alreadyPast {
                    scheduleToday(id: eveningID,
                                  body: "Your streak is at risk. Still time.",
                                  hour: eveningHour,
                                  minute: eveningMinute)
                }
            }

            // Streak lost — fires at 9AM tomorrow if streak is live but today's goal unmet.
            // Cancelled on the next foreground if the user reads before midnight.
            if streak > 0, !hasReadToday {
                scheduleNextDay(id: streakLostID,
                                body: "Your streak ended. Start again.",
                                hour: 9,
                                minute: 0)
            }
        }
    }

    // MARK: - Daily Edition

    static func fireEditionReady(count: Int) {
        guard UserDefaults.standard.bool(forKey: editionEnabledKey) else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = makeContent(body: "Today's Edition is ready. \(count) article\(count == 1 ? "" : "s").")
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: editionID, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Rank Up

    static func checkAndFireRankUp(previousCount: Int, context: ModelContext) {
        let entries = (try? context.fetch(FetchDescriptor<BrainEntry>())) ?? []
        let oldRank = BrainEngine.rank(for: previousCount)
        let newRank = BrainEngine.rank(for: entries.count)
        guard newRank != oldRank else { return }
        fireRankUp(rank: newRank)
    }

    static func fireRankUp(rank: BrainRank) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = makeContent(body: "Your Brain is now a \(rank.rawValue).")
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "je.notification.rankUp.\(rank.rawValue)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Helpers

    private static func scheduleToday(id: String, body: String, hour: Int, minute: Int) {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id,
                                            content: makeContent(body: body),
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static func scheduleNextDay(id: String, body: String, hour: Int, minute: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return }
        var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour   = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id,
                                            content: makeContent(body: body),
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static func makeContent(body: String) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = "Just\u{2026}"
        c.body  = body
        c.sound = .default
        return c
    }
}
