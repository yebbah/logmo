import Foundation
import SwiftData

/// Saving, confirming and repeating a campaign's weekly goals. The rules live in PlanRules.
@MainActor
enum PlanStore {
    private static func records(_ context: ModelContext, _ campaignID: UUID) -> [WeekGoal] {
        let all = (try? context.fetch(FetchDescriptor<WeekGoal>())) ?? []
        return all.filter { $0.campaignID == campaignID }
    }

    /// This campaign's goals by Monday, including copies that haven't been confirmed.
    static func byWeek(_ context: ModelContext, campaignID: UUID) -> [Date: GoalSet] {
        Dictionary(records(context, campaignID).map { ($0.weekStart, $0.goalSet) }, uniquingKeysWith: { a, _ in a })
    }

    private static func apply(_ s: GoalSet, to g: WeekGoal) {
        g.caloriesWeekly = s.caloriesWeekly
        g.caloriesAtOrUnder = s.caloriesAtOrUnder
        g.proteinDaily = s.proteinDaily
        g.stepsDaily = s.stepsDaily
        g.stepsIsWeeklyAverage = s.stepsIsWeeklyAverage
        g.waterDailyMl = s.waterDailyMl
        g.workoutDaysWeekly = s.workoutDaysWeekly
        g.carbsDaily = s.carbsDaily
        g.fatDaily = s.fatDaily
        g.confirmed = true
        g.updatedAt = Date()
    }

    /// Set a week's goals (new, or replacing what was there).
    static func save(_ context: ModelContext, campaignID: UUID, week: Date, goals: GoalSet) {
        let existing = records(context, campaignID).first { $0.weekStart == week }
        let g = existing ?? { let n = WeekGoal(weekStart: week, campaignID: campaignID); context.insert(n); return n }()
        apply(goals, to: g)
        try? context.save()
    }

    /// Keep the goals a week would otherwise only inherit: the user has decided they stand.
    static func confirm(_ context: ModelContext, campaignID: UUID, week: Date) {
        let recs = records(context, campaignID)
        if let g = recs.first(where: { $0.weekStart == week }) {
            g.confirmed = true; g.updatedAt = Date()
            try? context.save()
        } else if let eff = PlanRules.effective(Dictionary(recs.map { ($0.weekStart, $0.goalSet) }, uniquingKeysWith: { a, _ in a }), at: week) {
            save(context, campaignID: campaignID, week: week, goals: eff)
        }
    }

    /// Give several weeks the same goals (the "repeat" option).
    static func fill(_ context: ModelContext, campaignID: UUID, weeks: [Date], goals: GoalSet) {
        for w in weeks { save(context, campaignID: campaignID, week: w, goals: goals) }
    }

    /// The Mondays the user set or confirmed.
    static func explicitWeeks(_ goals: [WeekGoal], campaignID: UUID) -> Set<Date> {
        Set(goals.filter { $0.campaignID == campaignID && $0.confirmed }.map(\.weekStart))
    }
}
