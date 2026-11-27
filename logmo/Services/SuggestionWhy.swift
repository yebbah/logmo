import Foundation

/// The suggestion's two paces, and the reasons behind each in plain language. All of it is written from calculated facts.
extension SuggestionRules {
    struct PaceOptions: Equatable {
        var conservative: PlanSuggestion
        var aggressive: PlanSuggestion?        // nil when a faster pace isn't offered
        var aggressiveNote: String?            // why not, when it isn't
        func suggestion(_ pace: SuggestionPace) -> PlanSuggestion { pace == .aggressive ? (aggressive ?? conservative) : conservative }
    }

    /// Both paces for a week. Without a faster option the two are the same and `aggressive` is nil.
    static func options(_ s: WeekSummary) -> PaceOptions {
        var sc = s; sc.pace = .conservative
        var sa = s; sa.pace = .aggressive
        let ac = assess(sa)
        return PaceOptions(conservative: baseline(sc), aggressive: ac.aggressiveDelta != nil ? baseline(sa) : nil, aggressiveNote: ac.aggressiveNote)
    }

    // MARK: Why

    static func why(_ s: WeekSummary, _ a: Assessment, calories: Int, steps: Int, workouts: Int) -> [WhyItem] {
        var out: [WhyItem] = []
        func weight(_ kg: Double) -> String { s.useLb ? String(format: "%.1f lb", kg * 2.20462) : String(format: "%.1f kg", kg) }
        func weight2(_ kg: Double) -> String { s.useLb ? String(format: "%.2f lb", kg * 2.20462) : String(format: "%.2f kg", kg) }
        let kind = s.kind.title.lowercased()

        // Progress against what the campaign is for.
        if let w = s.weightChangeKgPerWeek {
            let amount = weight2(abs(w))
            switch (s.kind, a.rate) {
            case (.cut, .onTrack): out.append(.init(kind: .good, text: "Your weight trend is down about \(amount) a week, a steady pace for a cut."))
            case (.cut, .aboveBand): out.append(.init(kind: .warn, text: w <= 0 ? "Your weight trend is down only \(amount) a week, slower than a cut aims for." : "Your weight trend is up \(amount) a week, the wrong way for a cut."))
            case (.cut, .belowBand): out.append(.init(kind: .warn, text: "You're losing about \(amount) a week, faster than a cut aims for, so the plan holds back rather than pushing harder."))
            case (.bulk, .onTrack): out.append(.init(kind: .good, text: "Your weight trend is up about \(amount) a week, a steady gain for a bulk."))
            case (.bulk, .aboveBand): out.append(.init(kind: .warn, text: "You're gaining about \(amount) a week, faster than a bulk aims for. Faster gains tend to add more fat."))
            case (.bulk, .belowBand): out.append(.init(kind: .warn, text: w >= 0 ? "Your weight trend is up only \(amount) a week, slower than a bulk aims for." : "Your weight trend is down \(amount) a week, the wrong way for a bulk."))
            case (.maintenance, .onTrack): out.append(.init(kind: .good, text: "Your weight is steady (\(w >= 0 ? "up" : "down") \(amount) a week), which is what maintenance is for."))
            case (.maintenance, .aboveBand): out.append(.init(kind: .warn, text: "Your weight is drifting up, \(amount) a week."))
            case (.maintenance, .belowBand): out.append(.init(kind: .warn, text: "Your weight is drifting down, \(amount) a week."))
            default: break
            }
        } else {
            out.append(.init(kind: .info, text: "There aren't enough weigh-ins yet to read a trend, so the scale isn't steering this suggestion. Weighing in on most days will sharpen it."))
        }
        if let g = s.targetGapKg, s.kind != .maintenance {
            if abs(g) < 0.1 { out.append(.init(kind: .good, text: "You're at your target weight.")) }
            else if s.kind == .cut && g > 0 { out.append(.init(kind: .info, text: "You're \(weight(g)) above your target, so a steady pace gets you there.")) }
            else if s.kind == .bulk && g < 0 { out.append(.init(kind: .info, text: "You're \(weight(-g)) below your target, so a steady gain gets you there.")) }
        }

        // Intake against the plan.
        if let avg = s.avgCalories, let goal = s.current.caloriesWeekly.map({ Int((Double($0) / 7).rounded()) }) {
            switch a.intake {
            case .near: out.append(.init(kind: .good, text: "You ate close to your calorie goal (about \(fmt(avg)) against \(fmt(goal)) a day), so the scale is a fair read of the plan."))
            case .over: out.append(.init(kind: .warn, text: "You averaged \(fmt(avg)) a day, above your goal of \(fmt(goal)). Following the plan more closely comes before changing it."))
            case .under: out.append(.init(kind: .warn, text: "You averaged \(fmt(avg)) a day, below your goal of \(fmt(goal)), so the plan may be fine and the logs or the day-to-day eating are the gap."))
            case .unknown: break
            }
        } else if s.avgCalories == nil {
            out.append(.init(kind: .info, text: "No calories were logged in the days looked at, so intake isn't judged."))
        }

        // What the chosen pace means.
        if s.kind != .maintenance {
            let diff = calories - a.baseCalories
            var line: String
            if diff == 0 { line = "Calories stay at \(fmt(calories)) a day" + (a.rate == .onTrack ? ": nothing needs changing." : ", until the evidence is clearer.") }
            else if s.pace == .aggressive { line = "Aggressive pace: \(fmt(calories)) a day, \(abs(diff)) \(diff < 0 ? "less" : "more") than now." }
            else { line = "Conservative pace: a small change of \(abs(diff)) a day, \(diff < 0 ? "down" : "up") to \(fmt(calories)), so the plan stays easy to keep." }
            if let m = s.estimatedMaintenance, let e = Optional(Double(calories - m) / Maintenance.kcalPerKgPerWeekAsDaily), abs(e) >= 0.05 {
                line += " Against an estimated maintenance of \(fmt(m)), that points to about \(weight2(abs(e))) a week \(e < 0 ? "lost" : "gained")."
            }
            if s.pace == .aggressive && diff != 0 { line += " It works faster but is harder to keep up and tends to cost more hunger and energy." }
            out.append(.init(kind: .info, text: line))
        }

        out.append(contentsOf: measurementWhy(s))

        // Recovery, illness and the rest.
        let sick = s.sickDays ?? 0
        if sick > 0 {
            out.append(.init(kind: .warn, text: "You were sick on \(sick) \(sick == 1 ? "day" : "days"), so nothing harder is suggested this week."))
        } else if a.recovery == .poor {
            out.append(.init(kind: .warn, text: "Your check-ins point to strain (fatigue, soreness or sleep)" + (workouts < a.baseWorkouts ? ", so lifting goes from \(a.baseWorkouts) to \(workouts) days to help you recover." : ".")))
        } else if a.recovery == .good {
            out.append(.init(kind: .good, text: "Your check-ins look good: energy and recovery are holding up."))
        }
        if steps < a.baseSteps { out.append(.init(kind: .info, text: "Your steps goal comes down to \(fmt(steps)) because your logged average has been well below it.")) }
        if let p = s.periodDays, p > 0 { out.append(.init(kind: .info, text: "\(p) period \(p == 1 ? "day" : "days") this week can hold water and blur the scale, so those weigh-ins weren't read as a stall.")) }
        if a.confidence.forCalories == .low, let more = a.needMoreData.first { out.append(.init(kind: .info, text: "I'm not very sure yet. \(more)")) }
        return out
    }

    /// Body measurements as a second opinion beside the scale. They explain, and never change a number on their own.
    static func measurementWhy(_ s: WeekSummary) -> [WhyItem] {
        guard let m = s.measures else { return [] }
        func cm(_ v: Double) -> String { String(format: "%.1f", abs(v)) }
        let waists = [MeasureSite.navel, .belowNavel, .aboveNavel].compactMap { m.changes[$0] }
        let waist = m.changes[.navel] ?? (waists.isEmpty ? nil : waists.reduce(0, +) / Double(waists.count))
        let muscle = [MeasureSite.chest, .biceps, .thighs].compactMap { m.changes[$0] }
        let muscleDown = muscle.contains { $0 <= -1.5 }, muscleUp = muscle.contains { $0 >= 1.0 }
        let span = "\(m.spanDays) days"
        let site = m.changes[.navel] != nil ? "waist at the navel" : "waist"
        switch s.kind {
        case .cut:
            guard let w = waist else { return [] }
            if w <= -1.0 {
                let tail = muscleDown ? ", but your chest, arms or thighs are down too, so keep protein and lifting steady to protect muscle."
                                      : (muscle.isEmpty ? "." : ", while your chest, arms and thighs haven't shrunk, so the loss looks like fat rather than muscle.")
                return [.init(kind: .good, text: "Your \(site) is down \(cm(w)) cm over \(span)" + tail + " Measurements are a second opinion beside the scale and never change goals on their own.")]
            }
            if w >= 1.0 { return [.init(kind: .warn, text: "Your \(site) is up \(cm(w)) cm over \(span) even though you're cutting, so portions and tracking are worth a look.")] }
            if (s.weightChangePercentPerWeek ?? 0) <= -0.3 {
                return [.init(kind: .info, text: "The scale is moving but your \(site) hasn't changed yet (\(String(format: "%+.1f", w)) cm over \(span)). That can be water or muscle, so another measurement is worth having before cutting harder.")]
            }
            return []
        case .bulk:
            let w = waist ?? 0
            if w >= 2.0 { return [.init(kind: .warn, text: "Your \(site) is up \(cm(w)) cm over \(span), which can mean more of the gain is fat. A slower pace would keep it leaner.")] }
            if muscleUp { return [.init(kind: .good, text: "Your chest, arms or thighs are up while your \(site) moved only \(String(format: "%+.1f", w)) cm over \(span), so more of the gain looks like muscle.")] }
            return []
        case .maintenance:
            if m.changes.values.allSatisfy({ abs($0) < 1.0 }) { return [.init(kind: .good, text: "Your measurements are steady over \(span), which fits maintenance.")] }
            return []
        }
    }
}
