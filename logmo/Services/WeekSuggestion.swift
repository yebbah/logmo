import Foundation

/// What the assistant is allowed to see about one week: numbers only. No name, email, campaign label,
/// dates, notes or anything typed by the user. Built on the phone, shown to the user before anything runs.
struct WeekSummary: Equatable {
    var kind: CampaignKind
    var weekNumber: Int
    var totalWeeks: Int?
    var daysCovered: Int                       // days in the assessed window (fewer than 7 while the week is open)
    var daysLogged: Int
    var weightChangeKgPerWeek: Double?         // trend change, scaled to a week
    var weightChangePercentPerWeek: Double?    // the same as a percentage of the trend weight
    var avgCalories: Int?
    var avgProteinG: Int?
    var avgCarbsG: Int?
    var avgFatG: Int?
    var avgSteps: Int?
    var workoutDays: Int
    var dailyGoalDaysMet: Int
    var ratingAverages: [String: Double]       // this window, by rating
    var ratingChange: [String: Double]         // this window minus the one before, where both exist
    var periodDays: Int?                       // nil when not shared
    var sickDays: Int?                         // nil when not shared
    var current: GoalSet                       // the goals in force this week
}

/// Next week's proposed goals, with reasons. Always passes through `SuggestionRules.clamp`.
struct PlanSuggestion: Equatable {
    enum Source: Equatable { case appleIntelligence, basic }
    var caloriesPerDay: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var steps: Int
    var workoutDays: Int
    var waterMl: Int?
    var reasons: [String]
    var source: Source = .basic

    /// The goals to save: judging modes (at or under, steps as average) are kept from this week.
    func goalSet(keeping base: GoalSet) -> GoalSet {
        var g = base
        g.caloriesWeekly = caloriesPerDay * 7
        g.proteinDaily = proteinG
        g.carbsDaily = carbsG
        g.fatDaily = fatG
        g.stepsDaily = steps
        g.workoutDaysWeekly = workoutDays
        if let waterMl { g.waterDailyMl = waterMl }
        return g
    }
}

enum AssessedWeek: Equatable { case thisWeekSoFar, lastWeek }

enum SuggestionRules {
    // MARK: Building the summary

    static func summary(campaign c: CampaignInfo, snaps: [DaySnapshot], current: GoalSet?, window: AssessedWeek,
                        includeCycle: Bool, includeSick: Bool, today: Date, calendar cal: Calendar = .current) -> WeekSummary {
        let thisWeek = Metrics.weekStart(of: today, calendar: cal)
        let start = window == .thisWeekSoFar ? thisWeek : cal.date(byAdding: .day, value: -7, to: thisWeek)!
        let end = window == .thisWeekSoFar ? cal.startOfDay(for: today) : cal.date(byAdding: .day, value: -1, to: thisWeek)!
        let days = dates(from: start, to: end, cal)
        let before = dates(from: cal.date(byAdding: .day, value: -7, to: start)!, to: cal.date(byAdding: .day, value: -1, to: start)!, cal)
        let map = Dictionary(snaps.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let inWindow = days.compactMap { map[$0] }
        let goals = current ?? GoalSet()

        func avg(_ pick: (DaySnapshot) -> Int?) -> Int? {
            let v = inWindow.compactMap(pick); return v.isEmpty ? nil : Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
        }
        func ratingAvg(_ ds: [Date]) -> [String: Double] {
            var out: [String: Double] = [:]
            for r in Rating.allCases {
                let v = ds.compactMap { map[$0]?.ratings[r.rawValue] }
                if !v.isEmpty { out[r.rawValue] = Double(v.reduce(0, +)) / Double(v.count) }
            }
            return out
        }
        let now = ratingAvg(days), prev = ratingAvg(before)
        var change: [String: Double] = [:]
        for (k, v) in now { if let p = prev[k] { change[k] = v - p } }

        // Weight change per week: the least-squares slope of the weigh-ins in this window and the week before it
        // (daily weights are noisy, so a longer stretch is steadier). Needs weigh-ins spanning at least three days.
        let from = cal.date(byAdding: .day, value: -6, to: start)!
        let pts: [(x: Double, y: Double)] = dates(from: from, to: end, cal).compactMap { d in
            guard let w = map[d]?.weightKg else { return nil }
            return (Double(cal.dateComponents([.day], from: from, to: d).day ?? 0), w)
        }
        var perWeek: Double?, pct: Double?
        if pts.count >= 2, let lo = pts.map(\.x).min(), let hi = pts.map(\.x).max(), hi - lo >= 3 {
            let mx = pts.map(\.x).reduce(0, +) / Double(pts.count), my = pts.map(\.y).reduce(0, +) / Double(pts.count)
            let den = pts.map { ($0.x - mx) * ($0.x - mx) }.reduce(0, +)
            if den > 0 {
                let slope = pts.map { ($0.x - mx) * ($0.y - my) }.reduce(0, +) / den
                perWeek = slope * 7
                pct = my > 0 ? perWeek! / my * 100 : nil
            }
        }
        let met = days.filter { Metrics.dayGoalStatus(map[$0], goals: current).allMet }.count
        return WeekSummary(kind: c.kind, weekNumber: CampaignRules.weekNumber(c, today: today, calendar: cal), totalWeeks: c.plannedWeeks,
                           daysCovered: days.count, daysLogged: inWindow.filter { !$0.logged.isEmpty }.count,
                           weightChangeKgPerWeek: perWeek, weightChangePercentPerWeek: pct,
                           avgCalories: avg(\.calories), avgProteinG: avg(\.proteinG), avgCarbsG: avg(\.carbsG), avgFatG: avg(\.fatG),
                           avgSteps: avg(\.steps), workoutDays: inWindow.filter { $0.ratings["performance"] != nil }.count,
                           dailyGoalDaysMet: met, ratingAverages: now, ratingChange: change,
                           periodDays: includeCycle ? inWindow.filter(\.onPeriod).count : nil,
                           sickDays: includeSick ? inWindow.filter(\.isSick).count : nil, current: goals)
    }

    private static func dates(from a: Date, to b: Date, _ cal: Calendar) -> [Date] {
        guard a <= b else { return [] }
        let n = (cal.dateComponents([.day], from: a, to: b).day ?? 0) + 1
        return (0..<n).map { cal.date(byAdding: .day, value: $0, to: a)! }
    }

    /// Enough to say anything useful: three logged days.
    static func hasEnoughData(_ s: WeekSummary) -> Bool { s.daysLogged >= 3 }

    // MARK: The basic suggestion (also the starting point handed to the assistant)

    static func baseline(_ s: WeekSummary) -> PlanSuggestion {
        let baseCal = s.current.caloriesWeekly.map { Int((Double($0) / 7).rounded()) } ?? s.avgCalories ?? 2000
        let baseSteps = s.current.stepsDaily ?? s.avgSteps ?? 8000
        let baseWork = s.current.workoutDaysWeekly ?? max(s.workoutDays, 3)
        var cal = baseCal, steps = baseSteps, work = baseWork
        var reasons: [String] = []

        let sick = (s.sickDays ?? 0) > 0
        let period = (s.periodDays ?? 0) > 0
        let fatigue = s.ratingAverages["fatigue"], soreness = s.ratingAverages["soreness"], perf = s.ratingAverages["performance"]
        let fatigueRising = (s.ratingChange["fatigue"] ?? 0) >= 0.6
        let strained = (fatigue ?? 0) >= 4 || (soreness ?? 0) >= 4 || ((perf ?? 5) <= 2.5) || (fatigueRising && (fatigue ?? 0) >= 3.5)

        // 1. Calories from the weight trend, against what the campaign is for.
        if let pct = s.weightChangePercentPerWeek, let kg = s.weightChangeKgPerWeek {
            let rate = String(format: "%+.2f kg a week", kg)
            switch s.kind {
            case .cut:
                if pct > -0.3 { cal -= pct > 0 ? 150 : 100; reasons.append("Cut, trend \(rate): slower than a cut needs, so calories go down a little.") }
                else if pct < -1.0 { cal += 100; reasons.append("Cut, trend \(rate): faster than is sustainable, so calories go up a little to protect muscle and energy.") }
                else { reasons.append("Cut, trend \(rate): a good pace, so calories stay as they are.") }
            case .bulk:
                if pct < 0.1 { cal += pct < 0 ? 150 : 100; reasons.append("Bulk, trend \(rate): not gaining enough, so calories go up a little.") }
                else if pct > 0.6 { cal -= 100; reasons.append("Bulk, trend \(rate): gaining faster than needed, so calories come down a little to limit fat gain.") }
                else { reasons.append("Bulk, trend \(rate): a steady gain, so calories stay as they are.") }
            case .maintenance:
                if pct > 0.25 { cal -= 100; reasons.append("Maintenance, trend \(rate): drifting up, so calories come down a little.") }
                else if pct < -0.25 { cal += 100; reasons.append("Maintenance, trend \(rate): drifting down, so calories go up a little.") }
                else { reasons.append("Maintenance, trend \(rate): steady, so calories stay as they are.") }
            }
        } else {
            reasons.append("Not enough weigh-ins this week to read the trend, so calories stay as they are. Weigh in on a few more days for a firmer suggestion.")
        }

        // 2. Cycle: weigh-ins in a period week are mostly water, so don't push harder on a stall.
        if period, s.kind == .cut, cal < baseCal, (s.weightChangePercentPerWeek ?? -1) > -0.3 {
            cal = baseCal
            reasons.append("There were period days this week, which can hold water and hide progress, so the cut isn't pushed harder yet.")
        } else if period {
            reasons.append("Period days this week: weigh-ins on those days weren't read as a stall.")
        }

        // 3. Recovery and illness shape training and effort.
        if sick {
            if s.kind == .cut { cal = max(cal, baseCal) }
            steps = min(steps, baseSteps)
            work = max(work - ((s.sickDays ?? 0) >= 2 ? 1 : 0), 1)
            reasons.append("You were sick for \(s.sickDays ?? 0) day\((s.sickDays ?? 0) == 1 ? "" : "s"): no harder cut, no more steps, and lighter lifting while you recover.")
        }
        if strained {
            work = max(min(work, baseWork) - (sick ? 0 : 1), 1)
            if s.kind == .cut { cal = max(cal, baseCal) }
            reasons.append("Fatigue, soreness or training performance point to strain, so one lifting day fewer and no harder cut.")
        }

        // 4. Steps follow what was actually achievable.
        if let avg = s.avgSteps, !sick {
            if Double(avg) < Double(baseSteps) * 0.7 {
                steps = max(roundTo(Int(Double(avg) * 1.15), 500), 2000)
                reasons.append("Steps averaged \(avg.formatted()), well under the goal, so the goal is set closer to what is doable.")
            } else if s.kind == .cut, cal < baseCal, Double(avg) >= Double(baseSteps) * 0.95, !strained {
                steps = baseSteps + 1000
                reasons.append("The steps goal was met, so it goes up by 1,000 to help the slow trend.")
            }
        }

        // 5. Macros: protein is kept, the rest follow the calories.
        let fatShare = s.kind == .cut ? 0.27 : (s.kind == .bulk ? 0.25 : 0.28)
        let proteinShare = s.kind == .cut ? 0.32 : (s.kind == .bulk ? 0.25 : 0.28)
        let protein = s.current.proteinDaily ?? roundTo(Int(Double(cal) * proteinShare / 4), 5)
        let fat = roundTo(Int(Double(cal) * fatShare / 9), 1)
        let carbs = max(roundTo(Int((Double(cal) - Double(protein) * 4 - Double(fat) * 9) / 4), 5), 0)
        let hunger = s.ratingAverages["hunger"] ?? 0
        if s.kind == .cut, hunger >= 4.2 { reasons.append("Hunger was high (\(String(format: "%.1f", hunger)) of 5): keep protein and fibre up and expect the week to be hard.") }

        reasons.append(s.current.proteinDaily != nil
            ? "Protein stays at \(protein) g; carbs (\(carbs) g) and fat (\(fat) g) follow the calories as a guide."
            : "Macros are set from the calories: protein \(protein) g, carbs \(carbs) g, fat \(fat) g, as a guide.")
        if let goal = s.current.workoutDaysWeekly, !strained, !sick {
            reasons.append(s.workoutDays >= goal
                ? "You trained \(s.workoutDays) day\(s.workoutDays == 1 ? "" : "s") against a goal of \(goal), so lifting stays at \(work)."
                : "You trained \(s.workoutDays) of \(goal) planned days; lifting stays at \(work) rather than adding more.")
        }
        var p = PlanSuggestion(caloriesPerDay: cal, proteinG: protein, carbsG: carbs, fatG: fat, steps: steps,
                               workoutDays: work, waterMl: s.current.waterDailyMl, reasons: reasons)
        p = clamp(p, around: s)
        return p
    }

    // MARK: Guard rails

    /// Whatever proposed the numbers (rules or the assistant), they are held to these limits.
    static func clamp(_ p: PlanSuggestion, around s: WeekSummary) -> PlanSuggestion {
        var q = p
        let baseCal = s.current.caloriesWeekly.map { Int((Double($0) / 7).rounded()) } ?? s.avgCalories ?? p.caloriesPerDay
        let baseSteps = s.current.stepsDaily ?? s.avgSteps ?? p.steps
        let baseWork = s.current.workoutDaysWeekly ?? max(s.workoutDays, p.workoutDays)
        q.caloriesPerDay = min(max(p.caloriesPerDay, max(baseCal - 150, 1200)), baseCal + 150)
        if baseCal < 1200 { q.caloriesPerDay = baseCal }                   // never push someone below a floor they are already under
        q.steps = min(max(p.steps, max(baseSteps - 2000, 1000)), baseSteps + 2000)
        q.workoutDays = min(max(p.workoutDays, max(baseWork - 1, 0)), min(baseWork + 1, 7))
        // A cut never goes harder in a sick or strained week.
        let sick = (s.sickDays ?? 0) > 0
        let fatigue = s.ratingAverages["fatigue"] ?? 0, soreness = s.ratingAverages["soreness"] ?? 0
        if s.kind == .cut, sick || fatigue >= 4 || soreness >= 4 { q.caloriesPerDay = max(q.caloriesPerDay, baseCal) }
        q.proteinG = min(max(p.proteinG, 40), 300)
        q.carbsG = min(max(p.carbsG, 0), 800)
        q.fatG = min(max(p.fatG, 20), 200)
        if let w = p.waterMl { q.waterMl = min(max(w, 500), 6000) }
        q.reasons = Array(p.reasons.filter { !$0.isEmpty }.prefix(5))
        return q
    }

    private static func roundTo(_ v: Int, _ step: Int) -> Int { step <= 1 ? v : Int((Double(v) / Double(step)).rounded()) * step }
}
