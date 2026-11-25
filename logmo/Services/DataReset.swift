import Foundation
import SwiftData

/// Wipes everything the app stores. Each object is deleted individually and the save is
/// checked, so a failure is reported instead of leaving old data on screen.
@MainActor
enum DataReset {
    static func deleteAll(_ context: ModelContext, today: Date = Date()) throws {
        for log in try context.fetch(FetchDescriptor<DayLog>()) { context.delete(log) }
        for goal in try context.fetch(FetchDescriptor<WeekGoal>()) { context.delete(goal) }
        for campaign in try context.fetch(FetchDescriptor<Campaign>()) { context.delete(campaign) }
        try context.save()
        // Back to a fresh start: one open default campaign, and the dashboard shows the current one.
        UserDefaults.standard.set("current", forKey: "campaignFilter")
        UserDefaults.standard.set("", forKey: "setupDismissedOn")
        CampaignStore.tidy(context, today: today)
    }
}
