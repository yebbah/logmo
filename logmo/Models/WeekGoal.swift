import Foundation
import SwiftData

/// Goals for one Monday-to-Sunday week, normally set on the Sunday before.
/// CloudKit-compatible like DayLog: defaulted fields, no unique constraints.
/// One row per week is enforced in code (see GoalsEditor.save).
@Model
final class WeekGoal {
    var id: UUID = UUID()
    var weekStart: Date = Date()          // the Monday, start of day
    var updatedAt: Date = Date()

    var caloriesWeekly: Int?              // total kcal for the week
    var caloriesAtOrUnder: Bool = true    // false = the total should reach the goal
    var proteinDaily: Int?                // g per day
    var stepsDaily: Int?                  // steps per day
    var waterDailyMl: Int?                // ml per day

    init(weekStart: Date) {
        self.weekStart = weekStart
    }

    var goalSet: GoalSet {
        GoalSet(caloriesWeekly: caloriesWeekly, caloriesAtOrUnder: caloriesAtOrUnder,
                proteinDaily: proteinDaily, stepsDaily: stepsDaily, waterDailyMl: waterDailyMl)
    }
}

extension GoalTimeline {
    init(_ goals: [WeekGoal]) {
        self.init(byWeek: Dictionary(goals.map { ($0.weekStart, $0.goalSet) }, uniquingKeysWith: { a, _ in a }))
    }
}
