import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Asks Apple Intelligence (the on-device language model) to refine the basic suggestion and explain it.
/// Nothing leaves the iPhone. The model only ever sees a `WeekSummary` rendered as text, and whatever it
/// returns is clamped by `SuggestionRules.clamp`. Without Apple Intelligence the basic suggestion is used.
enum AIAdvisor {
    enum Availability: Equatable { case available, unavailable(String) }

    static var availability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .unavailable("This iPhone doesn't support Apple Intelligence.")
                case .appleIntelligenceNotEnabled: return .unavailable("Apple Intelligence is turned off in iOS Settings.")
                case .modelNotReady: return .unavailable("Apple Intelligence is still getting ready. Try again later.")
                @unknown default: return .unavailable("Apple Intelligence isn't available right now.")
                }
            }
        }
        #endif
        return .unavailable("Needs iOS 26 or later with Apple Intelligence.")
    }

    /// The text the model sees. Shown to the user in the preview, word for word.
    static func prompt(for s: WeekSummary, baseline b: PlanSuggestion) -> String {
        func g(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "n/a" }
        func n(_ v: Int?) -> String { v.map(String.init) ?? "n/a" }
        var lines = [
            "Campaign: \(s.kind.title), week \(s.weekNumber)" + (s.totalWeeks.map { " of \($0)" } ?? ""),
            "Days assessed: \(s.daysCovered), logged: \(s.daysLogged)",
            "Weight trend change per week: " + (s.weightChangeKgPerWeek.map { String(format: "%+.2f kg (%+.2f%%)", $0, s.weightChangePercentPerWeek ?? 0) } ?? "not enough weigh-ins"),
            "Average calories: \(n(s.avgCalories)) (goal \(n(s.current.caloriesWeekly.map { $0 / 7 })))",
            "Average protein / carbs / fat (g): \(n(s.avgProteinG)) / \(n(s.avgCarbsG)) / \(n(s.avgFatG))",
            "Average steps: \(n(s.avgSteps)) (goal \(n(s.current.stepsDaily)))",
            "Workout days: \(s.workoutDays) (goal \(n(s.current.workoutDaysWeekly)))",
            "Days with all daily goals met: \(s.dailyGoalDaysMet)",
            "Check-in averages (1-5; for fatigue, stress, hunger, soreness higher means more): " +
                Rating.allCases.compactMap { r in s.ratingAverages[r.rawValue].map { "\(r.rawValue) \(g($0))" } }.joined(separator: ", "),
        ]
        if let p = s.periodDays { lines.append("Period days this week: \(p)") }
        if let k = s.sickDays { lines.append("Sick days this week: \(k)") }
        lines.append("Rule-based starting point for next week: \(b.caloriesPerDay) kcal/day, protein \(b.proteinG) g, carbs \(b.carbsG) g, fat \(b.fatG) g, \(b.steps) steps, \(b.workoutDays) lifting days.")
        return lines.joined(separator: "\n")
    }

    static let instructions = """
    You help someone plan next week's nutrition and training goals for a fitness campaign (cut, bulk or maintenance). \
    Use only the numbers you are given. Start from the rule-based starting point and change it only when the data clearly says so. \
    Keep changes small: calories within 150 of this week's goal, steps within 2000, lifting days within 1. \
    On a cut never push harder in a week with sickness or high fatigue. A period can hide weight loss as water, so do not read it as a stall. \
    Give three or four short reasons in plain language, each tied to a number you were given. This is not medical advice.
    """

    /// The assistant's suggestion, clamped to the guard rails; nil when it can't run or fails (the caller keeps the basic one).
    static func suggest(_ s: WeekSummary, baseline b: PlanSuggestion) async -> PlanSuggestion? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), availability == .available {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt(for: s, baseline: b), generating: AIPlan.self)
                let a = response.content
                var p = PlanSuggestion(caloriesPerDay: a.caloriesPerDay, proteinG: a.proteinG, carbsG: a.carbsG, fatG: a.fatG,
                                       steps: a.steps, workoutDays: a.liftingDays, waterMl: b.waterMl, reasons: a.reasons,
                                       source: .appleIntelligence)
                p = SuggestionRules.clamp(p, around: s)
                if p.reasons.isEmpty { p.reasons = b.reasons }
                return p
            } catch { return nil }
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct AIPlan {
    @Guide(description: "Calories per day for next week") var caloriesPerDay: Int
    @Guide(description: "Protein in grams per day") var proteinG: Int
    @Guide(description: "Carbohydrate in grams per day") var carbsG: Int
    @Guide(description: "Fat in grams per day") var fatG: Int
    @Guide(description: "Steps per day") var steps: Int
    @Guide(description: "Number of lifting (workout) days next week, 0 to 7") var liftingDays: Int
    @Guide(description: "Three or four short reasons, each tied to a number from the data", .count(3...4)) var reasons: [String]
}
#endif
