import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence's part of the weekly suggestion. The app calculates every fact first (trends, averages, logging
/// coverage, adherence, confidence) and decides what the evidence supports. The on-device model is given those facts
/// as structured context and can only choose values between "keep" and what is supported, and add a short note.
/// Nothing it says is shown unless it passes `NoteValidator`; numbers outside the facts are rejected.
/// Nothing leaves the iPhone. Without Apple Intelligence the deterministic suggestion is used.
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

    // MARK: The structured context

    /// The facts the model sees, as labelled lines. All values are calculated by the app; shown to the user in the preview.
    static func facts(_ s: WeekSummary, _ a: Assessment) -> String {
        func g(_ v: Double?, _ f: String = "%.1f") -> String { v.map { String(format: f, $0) } ?? "unknown" }
        func n(_ v: Int?) -> String { v.map(String.init) ?? "unknown" }
        var l = [
            "campaign: \(s.kind.title), week \(s.weekNumber)" + (s.totalWeeks.map { " of \($0)" } ?? ""),
            "days assessed: \(s.daysCovered); days with any log: \(s.daysLogged)",
            "weight trend per week: " + (s.weightChangeKgPerWeek.map { String(format: "%+.2f kg (%+.2f%%)", $0, s.weightChangePercentPerWeek ?? 0) } ?? "unknown")
                + "; weigh-ins in 21 days: \(s.weighIns); status against campaign: \(a.rate); confidence: \(a.confidence.weight.title)",
            "calories per day: average \(n(s.avgCalories)), goal \(n(s.current.caloriesWeekly.map { $0 / 7 })), logged on \(s.calorieDays) days; intake vs goal: \(a.intake); confidence: \(a.confidence.nutrition.title)",
            "protein g: average \(n(s.avgProteinG)), goal \(n(s.current.proteinDaily))",
            "steps per day: average \(n(s.avgSteps)), goal \(n(s.current.stepsDaily)), logged on \(s.stepsDays) days; confidence: \(a.confidence.activity.title)",
            "workout days: \(s.workoutDays), goal \(n(s.current.workoutDaysWeekly))",
            "adherence overall: \(a.adherence)",
            "check-in averages (1-5; more fatigue, stress, hunger, soreness is worse): "
                + Rating.allCases.compactMap { r in s.ratingAverages[r.rawValue].map { "\(r.rawValue) \(g($0))" } }.joined(separator: ", ")
                + "; logged on \(s.ratingDays) days; recovery reading: \(a.recovery); confidence: \(a.confidence.recovery.title)",
        ]
        if let p = s.periodDays { l.append("period days: \(p)") }
        if let k = s.sickDays { l.append("sick days: \(k)") }
        if !a.cautions.isEmpty { l.append("cautions found by the app: " + a.cautions.joined(separator: " ")) }
        return l.joined(separator: "\n")
    }

    /// The whole prompt: facts, then what the evidence supports and the ranges the model may choose within.
    static func prompt(for s: WeekSummary, assessment a: Assessment) -> String {
        facts(s, a) + "\n\n" + """
        decision from the facts: calories \(a.baseCalories + a.caloriesDelta) a day (current \(a.baseCalories)), steps \(a.stepsTarget ?? a.baseSteps), lifting days \(a.baseWorkouts + a.workoutsDelta).
        you may choose calories between \(a.allowedCalories.lowerBound) and \(a.allowedCalories.upperBound), steps between \(a.allowedSteps.lowerBound) and \(a.allowedSteps.upperBound), lifting days between \(a.allowedWorkouts.lowerBound) and \(a.allowedWorkouts.upperBound).
        """
    }

    static let instructions = """
    You help someone plan next week's calories, steps and lifting days for a fitness campaign. The app has already calculated every number \
    and decided what the evidence supports. You do not calculate or judge the data. Choose values inside the ranges you are given; when unsure, \
    use the decision from the facts. Then write one short note (at most two sentences, plain and kind, no blame) that explains the choice in \
    terms of the facts, and says if confidence is low what more data would help. Use only numbers that appear in the facts. \
    Never say training is safe or unsafe, never give medical advice, never invent measurements.
    """

    /// The suggestion with the assistant's choices applied inside the allowed ranges, and its note if it passes the checks.
    /// nil when it can't run or fails; the caller keeps the deterministic one.
    static func suggest(_ s: WeekSummary, baseline b: PlanSuggestion) async -> PlanSuggestion? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), availability == .available {
            let a = SuggestionRules.assess(s)
            do {
                let session = LanguageModelSession(instructions: instructions)
                let text = prompt(for: s, assessment: a)
                let response = try await session.respond(to: text, generating: AIPlan.self)
                let c = response.content
                var p = SuggestionRules.compose(s, a, calories: c.caloriesPerDay, steps: c.steps, workouts: c.liftingDays, source: .appleIntelligence)
                p.note = NoteValidator.clean(c.coachNote, facts: text, targets: [p.caloriesPerDay, p.proteinG, p.carbsG, p.fatG, p.steps, p.workoutDays])
                return p
            } catch { return nil }
        }
        #endif
        return nil
    }
}

/// Keeps the model's note honest: no number that isn't in the facts or the targets, no safety or medical claims.
enum NoteValidator {
    static let banned = ["safe to", "unsafe", "not safe", "diagnos", "prescri", "guarantee", "medical advice", "you must", "you have to"]

    static func numbers(in text: String) -> Set<String> {
        var out = Set<String>()
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i].isNumber {
                var j = i; var tok = ""
                while j < chars.count, chars[j].isNumber || ((chars[j] == "," || chars[j] == ".") && j + 1 < chars.count && chars[j + 1].isNumber) {
                    if chars[j] != "," { tok.append(chars[j]) }
                    j += 1
                }
                out.insert(tok.hasPrefix("+") ? String(tok.dropFirst()) : tok); i = j
            } else { i += 1 }
        }
        return out
    }

    /// The note if it is short, makes no banned claim and uses only known numbers; otherwise nil.
    static func clean(_ note: String, facts: String, targets: [Int]) -> String? {
        let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 320 else { return nil }
        let lower = t.lowercased()
        if banned.contains(where: { lower.contains($0) }) { return nil }
        var known = numbers(in: facts)
        for x in targets { known.insert(String(x)) }
        for n in numbers(in: t) where !known.contains(n) { return nil }
        return t
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct AIPlan {
    @Guide(description: "Calories per day for next week, inside the allowed range") var caloriesPerDay: Int
    @Guide(description: "Steps per day for next week, inside the allowed range") var steps: Int
    @Guide(description: "Number of lifting days next week, inside the allowed range") var liftingDays: Int
    @Guide(description: "One or two short sentences explaining the choice using only numbers from the facts") var coachNote: String
}
#endif
