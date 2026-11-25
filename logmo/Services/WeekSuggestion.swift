import Foundation

// MARK: - Facts

/// How much to trust a measurement, from how much of it was logged. Missing logs are never read as zero:
/// they lower confidence instead.
enum DataConfidence: Int, Comparable, Equatable {
    case low = 0, medium, high
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    var title: String { ["Low", "Medium", "High"][rawValue] }
}

/// Confidence per kind of evidence: adequate calorie logs say nothing about the weight trend.
struct MetricConfidence: Equatable {
    var weight: DataConfidence
    var nutrition: DataConfidence
    var activity: DataConfidence
    var recovery: DataConfidence
    /// A calorie change needs both a reliable trend and calorie logs to attribute it to.
    var forCalories: DataConfidence { min(weight, nutrition) }
}

/// What the assistant is allowed to see about one week: numbers only, all calculated on the phone. No name,
/// email, campaign label, dates, notes or anything typed by the user. Shown to the user before anything runs.
struct WeekSummary: Equatable {
    var kind: CampaignKind
    var weekNumber: Int
    var totalWeeks: Int?
    var daysCovered: Int                       // days in the assessed window (fewer than 7 while the week is open)
    var daysLogged: Int
    // Weight: a slope over up to the last 21 days, not just the assessed week.
    var weightChangeKgPerWeek: Double?
    var weightChangePercentPerWeek: Double?
    var weighIns: Int                          // in those 21 days
    var weighSpanDays: Int                     // first to last weigh-in
    var weightNoiseKg: Double?                 // typical scatter of weigh-ins around the line
    var recentSlopePercent: Double?            // the last 7 days alone, to catch a recent change of direction
    var estimatedMaintenance: Int?             // average intake adjusted for the weight trend; nil without both
    // Averages over the assessed window, and on how many days each was logged.
    var avgCalories: Int?
    var avgProteinG: Int?
    var avgCarbsG: Int?
    var avgFatG: Int?
    var avgSteps: Int?
    var calorieDays: Int
    var proteinDays: Int
    var stepsDays: Int
    var ratingDays: Int
    var workoutDays: Int
    var dailyGoalDaysMet: Int
    var ratingAverages: [String: Double]       // this window, by rating
    var ratingChange: [String: Double]         // this window minus the one before, where both exist
    var periodDays: Int?                       // nil when not shared
    var sickDays: Int?                         // nil when not shared
    var current: GoalSet                       // the goals in force this week
}

enum RateStatus: Equatable { case unknown, onTrack, aboveBand, belowBand }
enum IntakeStatus: Equatable { case unknown, near, over, under }
enum Adherence: Equatable { case unknown, high, moderate, low }
enum RecoveryStatus: Equatable { case unknown, good, mixed, poor }

/// The deterministic reading of a week: what the facts say, how sure that is, and the changes the evidence supports.
/// The language model never overrides this: it can only choose values between "keep" and what is supported.
struct Assessment: Equatable {
    var confidence: MetricConfidence
    var rate: RateStatus
    var intake: IntakeStatus
    var adherence: Adherence
    var recovery: RecoveryStatus
    var baseCalories: Int
    var baseSteps: Int
    var baseWorkouts: Int
    var caloriesDelta: Int                     // 0 = keep
    var stepsTarget: Int?                      // nil = keep
    var workoutsDelta: Int                     // 0 or -1
    var allowedCalories: ClosedRange<Int>
    var allowedSteps: ClosedRange<Int>
    var allowedWorkouts: ClosedRange<Int>
    var evidence: [String]
    var cautions: [String]
    var needMoreData: [String]
}

/// Next week's proposed goals with the evidence behind them. Every text in it is written from calculated facts.
struct PlanSuggestion: Equatable {
    enum Source: Equatable { case appleIntelligence, basic }
    var caloriesPerDay: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var steps: Int
    var workoutDays: Int
    var waterMl: Int?
    var confidence: DataConfidence = .low
    var metricConfidence = MetricConfidence(weight: .low, nutrition: .low, activity: .low, recovery: .low)
    var headline: String = ""
    var evidence: [String] = []
    var cautions: [String] = []
    var needMoreData: [String] = []
    var note: String?                          // Apple Intelligence's own words, kept only if it passes the checks
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
    static let lowCalorieThreshold = 1500
    static let hardCalorieFloor = 1200
    static let maxDeficitFromMaintenance = 0.25

    /// Weekly weight change, as a percentage of body weight, that each campaign aims for.
    static func targetBand(_ kind: CampaignKind) -> ClosedRange<Double> {
        switch kind {
        case .cut: -1.0 ... -0.3
        case .bulk: 0.1 ... 0.5
        case .maintenance: -0.25 ... 0.25
        }
    }

    // MARK: Building the facts

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
        func count(_ pick: (DaySnapshot) -> Int?) -> Int { inWindow.compactMap(pick).count }
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

        // Weight change per week: the least-squares slope of the weigh-ins over up to the last 21 days. Daily weights
        // are noisy, so a longer stretch is steadier, and one odd weigh-in can't swing it.
        let from = cal.date(byAdding: .day, value: -20, to: end)!
        let pts: [(x: Double, y: Double)] = dates(from: from, to: end, cal).compactMap { d in
            guard let w = map[d]?.weightKg else { return nil }
            return (Double(cal.dateComponents([.day], from: from, to: d).day ?? 0), w)
        }
        let span = (pts.map(\.x).max() ?? 0) - (pts.map(\.x).min() ?? 0)
        var perWeek: Double?, pct: Double?, noise: Double?
        if let f = fit(pts), span >= 3 {
            perWeek = f.slope * 7
            pct = f.mean > 0 ? perWeek! / f.mean * 100 : nil
            noise = f.scatter
        }
        let recentPts = pts.filter { $0.x >= 14 }
        var recent: Double?
        if recentPts.count >= 3, let f = fit(recentPts), (recentPts.map(\.x).max()! - recentPts.map(\.x).min()!) >= 4, f.mean > 0 {
            recent = f.slope * 7 / f.mean * 100
        }
        let calorieDays = count(\.calories)
        var maintenance: Int?
        if let a = avg(\.calories), let w = perWeek, calorieDays >= 3, span >= 7 { maintenance = Int((Double(a) - w * 1100).rounded()) }

        let met = days.filter { Metrics.dayGoalStatus(map[$0], goals: current).allMet }.count
        return WeekSummary(kind: c.kind, weekNumber: CampaignRules.weekNumber(c, today: today, calendar: cal), totalWeeks: c.plannedWeeks,
                           daysCovered: days.count, daysLogged: inWindow.filter { !$0.logged.isEmpty }.count,
                           weightChangeKgPerWeek: perWeek, weightChangePercentPerWeek: pct, weighIns: pts.count,
                           weighSpanDays: Int(span), weightNoiseKg: noise, recentSlopePercent: recent, estimatedMaintenance: maintenance,
                           avgCalories: avg(\.calories), avgProteinG: avg(\.proteinG), avgCarbsG: avg(\.carbsG), avgFatG: avg(\.fatG),
                           avgSteps: avg(\.steps), calorieDays: calorieDays, proteinDays: count(\.proteinG), stepsDays: count(\.steps),
                           ratingDays: inWindow.filter { !$0.ratings.isEmpty }.count,
                           workoutDays: inWindow.filter { $0.ratings["performance"] != nil }.count,
                           dailyGoalDaysMet: met, ratingAverages: now, ratingChange: change,
                           periodDays: includeCycle ? inWindow.filter(\.onPeriod).count : nil,
                           sickDays: includeSick ? inWindow.filter(\.isSick).count : nil, current: goals)
    }

    private static func fit(_ pts: [(x: Double, y: Double)]) -> (slope: Double, mean: Double, scatter: Double?)? {
        guard pts.count >= 2 else { return nil }
        let n = Double(pts.count)
        let mx = pts.map(\.x).reduce(0, +) / n, my = pts.map(\.y).reduce(0, +) / n
        let den = pts.map { ($0.x - mx) * ($0.x - mx) }.reduce(0, +)
        guard den > 0 else { return nil }
        let slope = pts.map { ($0.x - mx) * ($0.y - my) }.reduce(0, +) / den
        var scatter: Double?
        if pts.count >= 3 {
            let ss = pts.map { p -> Double in let r = p.y - (my + slope * (p.x - mx)); return r * r }.reduce(0, +)
            scatter = (ss / (n - 2)).squareRoot()
        }
        return (slope, my, scatter)
    }

    private static func dates(from a: Date, to b: Date, _ cal: Calendar) -> [Date] {
        guard a <= b else { return [] }
        let n = (cal.dateComponents([.day], from: a, to: b).day ?? 0) + 1
        return (0..<n).map { cal.date(byAdding: .day, value: $0, to: a)! }
    }

    /// Anything logged at all: with less, the suggestion says what to log first.
    static func hasEnoughData(_ s: WeekSummary) -> Bool { s.daysLogged >= 1 }

    // MARK: Confidence

    static func coverageConfidence(days: Int) -> DataConfidence { days >= 5 ? .high : (days >= 3 ? .medium : .low) }

    static func weightConfidence(_ s: WeekSummary) -> DataConfidence {
        guard s.weightChangePercentPerWeek != nil else { return .low }
        var c: DataConfidence = s.weighIns >= 6 && s.weighSpanDays >= 12 ? .high : (s.weighIns >= 4 && s.weighSpanDays >= 7 ? .medium : .low)
        if let noise = s.weightNoiseKg, noise > 0.6, c > .low { c = DataConfidence(rawValue: c.rawValue - 1)! }   // scattered weigh-ins count for less
        return c
    }

    // MARK: Assessment

    static func assess(_ s: WeekSummary) -> Assessment {
        let band = targetBand(s.kind)
        let conf = MetricConfidence(weight: weightConfidence(s), nutrition: coverageConfidence(days: s.calorieDays),
                                    activity: coverageConfidence(days: s.stepsDays), recovery: coverageConfidence(days: s.ratingDays))
        let goalCal = s.current.caloriesWeekly.map { Int((Double($0) / 7).rounded()) }
        let baseCal = goalCal ?? s.avgCalories ?? 2000
        let baseSteps = s.current.stepsDaily ?? s.avgSteps ?? 8000
        let baseWork = s.current.workoutDaysWeekly ?? max(s.workoutDays, 3)
        var evidence: [String] = [], cautions: [String] = [], needMore: [String] = []

        // Weight against what the campaign is for.
        var rate: RateStatus = .unknown
        if let pct = s.weightChangePercentPerWeek, let kg = s.weightChangeKgPerWeek {
            rate = pct > band.upperBound ? .aboveBand : (pct < band.lowerBound ? .belowBand : .onTrack)
            evidence.append("Your weight trend is \(String(format: "%+.2f", kg)) kg a week (\(String(format: "%+.2f", pct))%) over \(s.weighSpanDays + 1) days from \(s.weighIns) weigh-ins, "
                            + "\(rateWords(s.kind, rate)). \(s.kind.title) aims for \(bandText(band)) a week.")
        } else {
            evidence.append("There aren't enough weigh-ins yet to read a trend (\(s.weighIns) in the last 21 days).")
        }

        // Intake against the target. Missing logs are never zero.
        var intake: IntakeStatus = .unknown
        if let avgC = s.avgCalories {
            let line = "You averaged \(fmt(avgC)) kcal a day" + (goalCal.map { " against a goal of \(fmt($0))" } ?? "") + ", logged on \(s.calorieDays) of \(s.daysCovered) days."
            evidence.append(line)
            if let g = goalCal, g > 0, conf.nutrition >= .medium {
                let r = Double(avgC) / Double(g)
                intake = r > 1.08 ? .over : (r < 0.92 ? .under : .near)
            }
        } else {
            evidence.append("No calories were logged in the days assessed, so intake isn't judged.")
        }
        if let p = s.avgProteinG, let gp = s.current.proteinDaily, s.proteinDays >= 1 {
            evidence.append("Protein averaged \(p) g against a goal of \(gp) g (\(s.proteinDays) days logged).")
        }

        // Adherence: is the user following the plan?
        var met: [Bool] = []
        if conf.nutrition >= .medium, intake != .unknown { met.append(intake == .near) }
        if let p = s.avgProteinG, let gp = s.current.proteinDaily, s.proteinDays >= 3 { met.append(Double(p) >= 0.9 * Double(gp)) }
        if let a = s.avgSteps, let gs = s.current.stepsDaily, conf.activity >= .medium { met.append(Double(a) >= 0.9 * Double(gs)) }
        if let gw = s.current.workoutDaysWeekly {
            let expected = Int((Double(gw) * Double(s.daysCovered) / 7).rounded(.down))
            if expected >= 1 { met.append(s.workoutDays >= expected) }
        }
        let share = met.isEmpty ? 0 : Double(met.filter { $0 }.count) / Double(met.count)
        let adherence: Adherence = met.count < 2 ? .unknown : (share >= 0.75 ? .high : (share >= 0.5 ? .moderate : .low))

        // Activity lines.
        var stepsTarget: Int?
        if let a = s.avgSteps {
            evidence.append("Steps averaged \(fmt(a)) a day" + (s.current.stepsDaily.map { " against a goal of \(fmt($0))" } ?? "") + ", logged on \(s.stepsDays) of \(s.daysCovered) days.")
            if let gs = s.current.stepsDaily, conf.activity >= .high, Double(a) < 0.6 * Double(gs) {      // lowering a goal needs a solid week of data
                stepsTarget = max(roundTo(Int(Double(a) * 1.25), 500), gs - 2000)
            }
        } else {
            needMore.append("Log your steps on a few more days so the steps goal can be checked.")
        }
        if let gw = s.current.workoutDaysWeekly {
            evidence.append("You trained on \(s.workoutDays) \(s.workoutDays == 1 ? "day" : "days") against a goal of \(gw) a week.")
        }

        // Recovery and biofeedback.
        let r = s.ratingAverages, rc = s.ratingChange
        let fatigue = r["fatigue"], soreness = r["soreness"], perf = r["performance"], sleep = r["sleep"]
        let hunger = r["hunger"], appetite = r["appetite"]
        let sick = s.sickDays ?? 0
        let strain = (fatigue ?? 0) >= 4 || (soreness ?? 0) >= 4 || (perf.map { $0 <= 2.5 } ?? false) || (sleep.map { $0 <= 2.2 } ?? false)
            || ((rc["fatigue"] ?? 0) >= 0.6 && (fatigue ?? 0) >= 3.5)
        var contradictions: [String] = []
        if let p = perf, let f = fatigue, p >= 4, f >= 4 { contradictions.append("Training performance is high while fatigue is also high, so recovery is hard to read.") }
        if let h = hunger, let a = appetite, h >= 4, a <= 2 { contradictions.append("Hunger is high while appetite is low, which don't usually go together.") }
        if let f = fatigue, let sl = sleep, f <= 2, sl <= 2 { contradictions.append("Sleep is poor but fatigue is low, which is unusual.") }
        var recovery: RecoveryStatus
        if sick > 0 || strain { recovery = .poor }
        else if conf.recovery == .low { recovery = .unknown }
        else if !contradictions.isEmpty { recovery = .mixed }
        else if (fatigue ?? 0) <= 3, (soreness ?? 0) <= 3.2, (perf ?? 3) >= 3, (sleep ?? 3) >= 3 { recovery = .good }
        else { recovery = .mixed }
        if !r.isEmpty {
            let parts = ["fatigue", "sleep", "soreness", "hunger", "stress", "performance"].compactMap { k -> String? in
                guard let v = r[k] else { return nil }
                let d = rc[k].map { abs($0) >= 0.3 ? String(format: " (%+.1f on the week before)", $0) : "" } ?? ""
                return "\(k) \(String(format: "%.1f", v))\(d)"
            }
            evidence.append("Check-ins (\(s.ratingDays) \(s.ratingDays == 1 ? "day" : "days")): \(parts.joined(separator: ", ")).")
        } else {
            needMore.append("Fill in the daily check-in on a few days so recovery can be read.")
        }
        if sick > 0 { evidence.append("You were sick on \(sick) \(sick == 1 ? "day" : "days") this week.") }
        if let p = s.periodDays, p > 0 { evidence.append("\(p) period \(p == 1 ? "day" : "days") this week, which can hold water and blur the scale.") }

        // Calories: only change when the evidence says the target (not the effort) is off.
        var delta = 0
        let need: Int = rate == .aboveBand ? -1 : (rate == .belowBand ? 1 : 0)
        let lowTarget = baseCal < lowCalorieThreshold
            || (conf.forCalories >= .medium && s.estimatedMaintenance.map { Double(baseCal) < (1 - maxDeficitFromMaintenance) * Double($0) } == true)
        let recentDisagrees: Bool = {
            guard let rp = s.recentSlopePercent, let pct = s.weightChangePercentPerWeek else { return false }
            return (rp > band.upperBound) != (pct > band.upperBound) || (rp < band.lowerBound) != (pct < band.lowerBound)
        }()
        if need != 0 {
            if conf.weight < .medium {
                needMore.append("Weigh in on at least four days a week for two weeks so the trend can be trusted.")
            } else if conf.nutrition < .medium {
                needMore.append("Log your calories on at least three or four days so a change in the scale can be linked to what you ate.")
            } else if recentDisagrees {
                cautions.append("The last 7 days point a different way from the longer trend, so the target stays while that settles.")
            } else if intake == .near {
                delta = need * step(s.kind, need: need, pct: s.weightChangePercentPerWeek ?? 0, band: band)
            } else if (need < 0 && intake == .over) || (need > 0 && intake == .under) {
                cautions.append("Your intake has been \(intake == .over ? "above" : "below") your target, which by itself could explain the scale. The target may be fine; following it more closely comes first.")
            } else if intake != .unknown {
                contradictions.append("Your logged intake and your weight point in opposite directions, so the logs may be incomplete.")
            }
        } else if s.kind == .cut, conf.recovery >= .medium, conf.nutrition >= .medium, intake == .near,
                  (hunger ?? 0) >= 4, (fatigue ?? 0) >= 3.8 {
            delta = 100                                                     // hunger and low energy together: review the target
            cautions.append("Hunger and fatigue are both high, which is worth reviewing even though the weight is on track.")
        }
        if delta < 0 {
            let reason: String? = sick > 0 ? "you were sick" : (strain ? "recovery looks strained" : (s.kind == .cut && (s.periodDays ?? 0) > 0 ? "period days can mask progress on the scale" : (s.kind == .cut && (hunger ?? 0) >= 4.2 ? "hunger is high" : nil)))
            if let reason { delta = 0; cautions.append("A lower calorie target would be supported by the trend, but isn't suggested because \(reason).") }
            else if lowTarget { delta = 0 }
            else if baseCal + delta < hardCalorieFloor { delta = 0 }
        }
        if lowTarget {
            cautions.append("Your calorie target is already low (\(fmt(baseCal)) a day"
                            + (s.estimatedMaintenance.map { ", about \(Int((1 - Double(baseCal) / Double($0)) * 100))% below your estimated maintenance" } ?? "")
                            + "), so it won't be lowered further. If it's hard to sustain, a doctor or dietitian can help.")
        }
        cautions.append(contentsOf: contradictions)
        if conf.forCalories == .low && need == 0 && rate == .unknown && !needMore.contains(where: { $0.hasPrefix("Weigh in") }) {
            needMore.append("Weigh in on at least four days a week for two weeks so the trend can be trusted.")
        }

        // Training: never raised on a self-report, lowered when recovery is strained or illness took days.
        var workoutsDelta = 0
        if (sick >= 2 || strain) && baseWork > 1 { workoutsDelta = -1 }
        let steps: Int? = sick > 0 ? nil : stepsTarget                    // illness is no moment to rework the steps goal
        let lo = min(baseCal, baseCal + delta), hi = max(baseCal, baseCal + delta)
        return Assessment(confidence: conf, rate: rate, intake: intake, adherence: adherence, recovery: recovery,
                          baseCalories: baseCal, baseSteps: baseSteps, baseWorkouts: baseWork, caloriesDelta: delta, stepsTarget: steps,
                          workoutsDelta: workoutsDelta, allowedCalories: lo...hi,
                          allowedSteps: min(baseSteps, steps ?? baseSteps)...baseSteps,
                          allowedWorkouts: max(baseWork + workoutsDelta, 0)...baseWork,
                          evidence: evidence, cautions: cautions, needMoreData: needMore)
    }

    /// Size of a calorie move, by campaign. Raising a cut or a bulk is always the larger of the two when the
    /// weight is going the wrong way; lowering is kept small.
    private static func step(_ kind: CampaignKind, need: Int, pct: Double, band: ClosedRange<Double>) -> Int {
        switch kind {
        case .cut: return need > 0 ? (pct < band.lowerBound - 0.4 ? 150 : 100) : 100
        case .bulk: return need > 0 ? (pct <= -0.1 ? 150 : 100) : 100
        case .maintenance: return 100
        }
    }

    // MARK: Turning an assessment into a suggestion

    /// The suggestion for the chosen numbers: whatever proposed them, they are clamped to what the evidence supports,
    /// macros are rebuilt to add up, and the text is written from the calculated facts.
    static func compose(_ s: WeekSummary, _ a: Assessment, calories: Int, steps: Int, workouts: Int,
                        source: PlanSuggestion.Source = .basic, note: String? = nil) -> PlanSuggestion {
        let cal = min(max(calories, a.allowedCalories.lowerBound), a.allowedCalories.upperBound)
        let st = min(max(steps, a.allowedSteps.lowerBound), a.allowedSteps.upperBound)
        let wk = min(max(workouts, a.allowedWorkouts.lowerBound), a.allowedWorkouts.upperBound)
        var m = macros(calories: cal, proteinGoal: s.current.proteinDaily, kind: s.kind)
        if cal == a.baseCalories, let c = s.current.carbsDaily, let f = s.current.fatDaily, let p = s.current.proteinDaily { m = (p, c, f) }   // kept: leave the user's macros alone
        let overall = a.confidence.forCalories
        let diff = cal - a.baseCalories
        var head: String
        if diff == 0 {
            head = "Keep calories at \(fmt(cal)) a day" + (overall == .low ? " for now." : ".")
            if overall == .low { head += " There isn't enough evidence yet to say whether it needs to change." }
        } else {
            head = "\(diff > 0 ? "Raise" : "Lower") calories by \(abs(diff)) to \(fmt(cal)) a day."
        }
        var evidence = a.evidence
        if wk < a.baseWorkouts {
            evidence.append("Lifting goes from \(a.baseWorkouts) to \(wk) days so you can recover. That is about workload, not a judgement on whether training is safe.")
        } else if let g = s.current.workoutDaysWeekly, s.workoutDays < Int((Double(g) * Double(s.daysCovered) / 7).rounded(.down)) {
            evidence.append("Lifting stays at \(g) days; the goal isn't lowered just because fewer days were done.")
        } else {
            evidence.append("Lifting stays at \(wk) days. Check-in scores are self-reports, so they don't show whether pushing harder is wise.")
        }
        if st < a.baseSteps { evidence.append("The steps goal comes down to \(fmt(st)) because your logged average has been well below it.") }
        return PlanSuggestion(caloriesPerDay: cal, proteinG: m.protein, carbsG: m.carbs, fatG: m.fat, steps: st, workoutDays: wk,
                              waterMl: s.current.waterDailyMl, confidence: overall, metricConfidence: a.confidence, headline: head,
                              evidence: evidence, cautions: a.cautions, needMoreData: a.needMoreData, note: note, source: source)
    }

    /// Protein stays as set; fat is a share of the calories; carbs take the rest, so 4P + 4C + 9F matches the calories.
    static func macros(calories: Int, proteinGoal: Int?, kind: CampaignKind) -> (protein: Int, carbs: Int, fat: Int) {
        let fatShare = kind == .cut ? 0.27 : (kind == .bulk ? 0.25 : 0.28)
        let proteinShare = kind == .cut ? 0.32 : (kind == .bulk ? 0.25 : 0.28)
        let protein = min(max(proteinGoal ?? roundTo(Int(Double(calories) * proteinShare / 4), 5), 40), 300)
        var fat = max(roundTo(Int(Double(calories) * fatShare / 9), 1), 20)
        var carbs = Int(((Double(calories) - Double(protein) * 4 - Double(fat) * 9) / 4).rounded())
        if carbs < 0 {                                                       // protein alone takes most of a low target
            fat = max(20, Int((Double(calories) - Double(protein) * 4) / 9)); carbs = max(Int(((Double(calories) - Double(protein) * 4 - Double(fat) * 9) / 4).rounded()), 0)
        }
        return (protein, max(roundTo(carbs, 5), 0), fat)
    }

    /// The deterministic suggestion, also the starting point handed to the assistant.
    static func baseline(_ s: WeekSummary) -> PlanSuggestion {
        let a = assess(s)
        return compose(s, a, calories: a.baseCalories + a.caloriesDelta, steps: a.stepsTarget ?? a.baseSteps, workouts: a.baseWorkouts + a.workoutsDelta)
    }

    /// Whatever proposed the numbers (rules or the assistant), they are held to what the evidence supports and to
    /// the hard rails: never below the calorie floor, never raised past the current goal in steps or lifting.
    static func clamp(_ p: PlanSuggestion, around s: WeekSummary) -> PlanSuggestion {
        let a = assess(s)
        var q = compose(s, a, calories: p.caloriesPerDay, steps: p.steps, workouts: p.workoutDays, source: p.source, note: p.note)
        if q.caloriesPerDay < hardCalorieFloor && a.baseCalories >= hardCalorieFloor { q.caloriesPerDay = hardCalorieFloor }
        return q
    }

    // MARK: Helpers

    private static func rateWords(_ kind: CampaignKind, _ r: RateStatus) -> String {
        switch (kind, r) {
        case (_, .onTrack): return "in the range this campaign aims for"
        case (.cut, .aboveBand): return "slower than a cut aims for, or rising"
        case (.cut, .belowBand): return "faster than a cut aims for"
        case (.bulk, .aboveBand): return "faster than a bulk aims for"
        case (.bulk, .belowBand): return "slower than a bulk aims for, or falling"
        case (.maintenance, .aboveBand): return "drifting up"
        case (.maintenance, .belowBand): return "drifting down"
        default: return "not yet readable"
        }
    }
    private static func bandText(_ b: ClosedRange<Double>) -> String {
        b.lowerBound < 0 && b.upperBound > 0 ? "within ±\(String(format: "%.2f", b.upperBound))%"
            : "\(String(format: "%.1f", abs(b.lowerBound)))–\(String(format: "%.1f", abs(b.upperBound)))% \(b.upperBound < 0 ? "loss" : "gain")"
    }
    static func fmt(_ v: Int) -> String { v.formatted() }
    private static func roundTo(_ v: Int, _ step: Int) -> Int { step <= 1 ? v : Int((Double(v) / Double(step)).rounded()) * step }
}
