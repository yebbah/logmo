import Foundation
import SwiftData

/// Goals for one Monday-to-Sunday week, normally set on the Sunday before.
/// CloudKit-compatible like DayLog: defaulted fields, no unique constraints.
/// One row per week is enforced in code (see GoalsEditor.save).
@Model
final class WeekGoal {
    var id: UUID = UUID()
    var campaignID: UUID?                 // the campaign these goals belong to (nil only before migration)
    var weekStart: Date = Date()          // the Monday, start of day
    var updatedAt: Date = Date()

    var caloriesWeekly: Int?              // total kcal for the week
    var caloriesAtOrUnder: Bool = true    // false = the total should reach the goal
    var proteinDaily: Int?                // g per day
    var stepsDaily: Int?                  // steps per day (the daily total, or the weekly average, see below)
    var stepsIsWeeklyAverage: Bool = false
    var workoutDaysWeekly: Int?           // target workout days per week
    /// true once the user set or confirmed this week. False for goals that were only copied in
    /// (a new campaign starts with a copy of the latest goals), shown as "carried over".
    var confirmed: Bool = true
    var waterDailyMl: Int?                // ml per day
    var carbsDaily: Int?                  // g per day, guidance only (never judged)
    var fatDaily: Int?                    // g per day, guidance only

    init(weekStart: Date, campaignID: UUID? = nil) {
        self.weekStart = weekStart
        self.campaignID = campaignID
    }

    var goalSet: GoalSet {
        GoalSet(caloriesWeekly: caloriesWeekly, caloriesAtOrUnder: caloriesAtOrUnder,
                proteinDaily: proteinDaily, stepsDaily: stepsDaily, stepsIsWeeklyAverage: stepsIsWeeklyAverage,
                waterDailyMl: waterDailyMl, workoutDaysWeekly: workoutDaysWeekly,
                carbsDaily: carbsDaily, fatDaily: fatDaily)
    }
}

extension WeekGoal {
    var stored: StoredGoal { StoredGoal(campaignID: campaignID, weekStart: weekStart, goals: goalSet) }
}

extension GoalTimeline {
    /// Every campaign's goals, looked up per campaign.
    init(_ goals: [WeekGoal], campaigns: [CampaignInfo]) {
        self.init(byWeek: [:], book: GoalRules.book(campaigns: campaigns, goals: goals.map(\.stored)))
    }

    /// One campaign's goals only (what the goals editor works on).
    init(_ goals: [WeekGoal], campaign: CampaignInfo) {
        let mine = goals.filter { ($0.campaignID ?? campaign.id) == campaign.id }
        self.init(byWeek: Dictionary(mine.map { ($0.weekStart, $0.goalSet) }, uniquingKeysWith: { a, _ in a }))
    }
}
