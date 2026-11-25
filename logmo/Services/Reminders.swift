import Foundation
import UserNotifications

/// The weekly plan reminder: a local notification, repeating once a week at a day and time the user picks.
/// It carries no personal data, only a nudge.
enum Reminders {
    static let weeklyPlanID = "logmo.weekly-plan-reminder"
    /// Sunday by default, at 18:00.
    static let defaultWeekday = 1
    static let defaultMinutes = 18 * 60

    /// Weekday numbering follows Calendar: Sunday = 1 … Saturday = 7. `minutes` is minutes after midnight.
    static func components(weekday: Int, minutes: Int) -> DateComponents {
        let m = min(max(minutes, 0), 24 * 60 - 1)
        return DateComponents(hour: m / 60, minute: m % 60, weekday: min(max(weekday, 1), 7))
    }

    /// Monday-first order for a picker, as (weekday, name).
    static let weekdays: [(Int, String)] = [(2, "Monday"), (3, "Tuesday"), (4, "Wednesday"), (5, "Thursday"),
                                            (6, "Friday"), (7, "Saturday"), (1, "Sunday")]

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func isAllowed() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    /// Replaces any existing reminder.
    static func schedule(weekday: Int, minutes: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyPlanID])
        let content = UNMutableNotificationContent()
        content.title = "Plan your week"
        content.body = "Set next week's goals in logmo."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components(weekday: weekday, minutes: minutes), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: weeklyPlanID, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [weeklyPlanID])
    }
}
