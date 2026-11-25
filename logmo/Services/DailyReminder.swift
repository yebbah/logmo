import Foundation
import SwiftData
import UserNotifications

/// The daily "log today" reminder: only sent on days the daily goals aren't done yet.
/// iOS can't decide at delivery time, so the app schedules one notification per day for the next week
/// and cancels today's as soon as the goals are met (when a log is saved, or the app is opened).
enum DailyReminderRules {
    static let defaultMinutes = 20 * 60                 // 20:00
    static let daysAhead = 7

    /// Is a reminder still needed for this day? With daily goals set: until they are all met (the weigh-in
    /// included). With none: until every required tracker is complete (or, if none is required, anything is logged).
    static func needsReminder(day: DaySnapshot?, goals: GoalSet?, required: Set<Tracker>) -> Bool {
        if goals?.hasDailyGoals == true { return !Metrics.dayGoalStatus(day, goals: goals).allMet }
        if required.isEmpty { return day?.logged.isEmpty ?? true }
        return !required.allSatisfy { day?.complete.contains($0) ?? false }
    }

    /// The moments to schedule: the chosen time on each of the next days, except today's when it has passed
    /// or today needs no reminder.
    static func fireDates(now: Date, minutes: Int, todayNeedsReminder: Bool, calendar cal: Calendar = .current) -> [Date] {
        let m = min(max(minutes, 0), 24 * 60 - 1)
        let start = cal.startOfDay(for: now)
        return (0..<daysAhead).compactMap { i -> Date? in
            guard let day = cal.date(byAdding: .day, value: i, to: start),
                  let at = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day) else { return nil }
            if at <= now { return nil }
            if i == 0 && !todayNeedsReminder { return nil }
            return at
        }
    }
}

@MainActor
enum DailyReminder {
    static let idPrefix = "logmo.daily-reminder."

    /// Re-plan the notifications from the stored data. Call after a log is saved, when the app opens or
    /// leaves the foreground, and when the switch or the time changes.
    static func refresh(_ context: ModelContext, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.standard
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard defaults.bool(forKey: SettingsKey.dailyReminderOn) else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let logs = (try? context.fetch(FetchDescriptor<DayLog>())) ?? []
        let goals = (try? context.fetch(FetchDescriptor<WeekGoal>())) ?? []
        let campaigns = ((try? context.fetch(FetchDescriptor<Campaign>())) ?? []).map(\.info)
        let todays = logs.first { cal.isDate($0.day, inSameDayAs: today) }?.snapshot
        let required = RequiredTrackers.parse(defaults.string(forKey: SettingsKey.required) ?? RequiredTrackers.defaultRaw)
        let todayGoals = GoalTimeline(goals, campaigns: campaigns).goals(forDay: today)
        let needs = DailyReminderRules.needsReminder(day: todays, goals: todayGoals, required: required)
        let minutes = defaults.object(forKey: SettingsKey.dailyReminderMinutes) as? Int ?? DailyReminderRules.defaultMinutes

        for at in DailyReminderRules.fireDates(now: now, minutes: minutes, todayNeedsReminder: needs) {
            let content = UNMutableNotificationContent()
            content.title = "Time to log"
            content.body = "You haven't finished today's goals in logmo yet."
            content.sound = .default
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            let id = idPrefix + String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            try? await center.add(UNNotificationRequest(identifier: id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false)))
        }
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
