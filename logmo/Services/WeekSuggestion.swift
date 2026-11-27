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

/// How hard a suggestion pushes: a small, easy-to-keep change, or a faster one. The Settings preference decides which leads.
enum SuggestionPace: String, CaseIterable, Identifiable {
    case conservative, aggressive
    var id: String { rawValue }
    var title: String { self == .conservative ? "Conservative" : "Aggressive" }
    static func saved() -> SuggestionPace { SuggestionPace(rawValue: UserDefaults.standard.string(forKey: SettingsKey.pace) ?? "") ?? .conservative }
}

/// How body measurements moved over the campaign so far: latest reading minus the first, in cm, where two readings a week apart exist.
struct MeasureFacts: Equatable {
    var readings: Int
    var spanDays: Int
    var changes: [MeasureSite: Double]
}

/// One plain-language reason behind a suggestion.
struct WhyItem: Equatable {
    enum Kind: Equatable { case good, info, warn }
    var kind: Kind
    var text: String
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
    var estimatedMaintenance: Int?             // estimated maintenance calories (TDEE), from the logs or the formula; nil without either
    var maintenanceSource: MaintenanceSource?
    var maintenanceStatus: MaintenanceStatus?  // updating: recent weigh-ins and calorie logs are enough to move it; waiting: held
    var maintenanceConfidence: DataConfidence?
    var formulaMaintenance: Int?               // from height, age, sex and activity, when set
    var trendWeightKg: Double?                 // used here to size a calorie change; never shown or sent
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
    var avgRestingHR: Int?                     // from Apple Health, over the assessed days
    var restingHRChange: Double?               // bpm, against the week before
    var avgHRV: Int?
    var hrvChangePercent: Double?              // against the week before
    var sleepNights: Int                       // nights Health recorded sleep
    var avgSleepMinutes: Int?
    var periodDays: Int?                       // nil when not shared
    var sickDays: Int?                         // nil when not shared
    var current: GoalSet                       // the goals in force this week
    var pace: SuggestionPace = .conservative   // which pace this assessment leads with
    var measures: MeasureFacts? = nil          // body measurements over the campaign; nil without two readings a week apart
    var targetGapKg: Double? = nil             // trend weight minus the campaign's target weight; nil without a target (used locally only)
    var useLb: Bool = false                    // how to word weights in the text (used locally only)
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
    var conservativeDelta: Int = 0             // the calorie move at the conservative pace
    var aggressiveDelta: Int? = nil            // the calorie move at the aggressive pace; nil when it isn't offered
    var aggressiveNote: String? = nil          // why it isn't offered (or what it means)
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
    var pace: SuggestionPace = .conservative
    var expectedKgPerWeek: Double? = nil       // the trend change this calorie target points to, from estimated maintenance
    var why: [WhyItem] = []                    // the reasons in plain language

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
    static let aggressiveStepLimit = 250                 // kcal a day: the most the aggressive pace moves the target in one week (conservative moves by 100 to 150)

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
                        includeCycle: Bool, includeSick: Bool, today: Date, smoothingDays: Int = 16, seeds: [Date: Double] = [:], profile: MaintenanceProfile? = nil,
                        pace: SuggestionPace = .conservative, measurements: [MeasureEntry] = [], useLb: Bool = false,
                        calendar cal: Calendar = .current) -> WeekSummary {
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
        func avgD(_ ds: [Date], _ pick: (DaySnapshot) -> Int?) -> Double? {
            let v = ds.compactMap { map[$0].flatMap(pick) }
            return v.isEmpty ? nil : Double(v.reduce(0, +)) / Double(v.count)
        }
        let hr = avgD(days) { $0.restingHR }, hrPrev = avgD(before) { $0.restingHR }
        let hv = avgD(days) { $0.hrv }, hvPrev = avgD(before) { $0.hrv }
        let sleep = avgD(days) { $0.sleepMinutes }
        let calorieDays = count(\.calories)
        let maintenance = Maintenance.estimate(snaps, through: end, smoothingDays: smoothingDays, seeds: seeds, profile: profile, calendar: cal)
        let trendKg = Metrics.weightTrend(snaps, through: end, smoothingDays: smoothingDays, seeds: seeds, calendar: cal).last?.trendKg

        let met = days.filter { Metrics.dayGoalStatus(map[$0], goals: current).allMet }.count
        var measureFacts: MeasureFacts?
        let mine = MeasureRules.entries(measurements, in: c, through: end, calendar: cal)
        if mine.count >= 2 {
            let ch = MeasureRules.changes(mine, calendar: cal)
            if !ch.isEmpty { measureFacts = MeasureFacts(readings: mine.count, spanDays: cal.dateComponents([.day], from: mine.first!.day, to: mine.last!.day).day ?? 0, changes: ch) }
        }
        let gap: Double? = c.targetWeightKg.flatMap { t in trendKg.map { $0 - t } }
        return WeekSummary(kind: c.kind, weekNumber: CampaignRules.weekNumber(c, today: today, calendar: cal), totalWeeks: c.plannedWeeks,
                           daysCovered: days.count, daysLogged: inWindow.filter { !$0.logged.isEmpty }.count,
                           weightChangeKgPerWeek: perWeek, weightChangePercentPerWeek: pct, weighIns: pts.count,
                           weighSpanDays: Int(span), weightNoiseKg: noise, recentSlopePercent: recent, estimatedMaintenance: maintenance?.kcalPerDay,
                           maintenanceSource: maintenance?.source, maintenanceStatus: maintenance?.status, maintenanceConfidence: maintenance?.confidence,
                           formulaMaintenance: maintenance?.formulaKcal, trendWeightKg: trendKg,
                           avgCalories: avg(\.calories), avgProteinG: avg(\.proteinG), avgCarbsG: avg(\.carbsG), avgFatG: avg(\.fatG),
                           avgSteps: avg(\.steps), calorieDays: calorieDays, proteinDays: count(\.proteinG), stepsDays: count(\.steps),
                           ratingDays: inWindow.filter { !$0.ratings.isEmpty }.count,
                           workoutDays: inWindow.filter { $0.ratings["performance"] != nil }.count,
                           dailyGoalDaysMet: met, ratingAverages: now, ratingChange: change,
                           avgRestingHR: hr.map { Int($0.rounded()) }, restingHRChange: hr.flatMap { h in hrPrev.map { h - $0 } },
                           avgHRV: hv.map { Int($0.rounded()) }, hrvChangePercent: hv.flatMap { h in hvPrev.map { $0 > 0 ? (h - $0) / $0 * 100 : 0 } },
                           sleepNights: inWindow.filter { $0.sleepMinutes != nil }.count, avgSleepMinutes: sleep.map { Int($0.rounded()) },
                           periodDays: includeCycle ? inWindow.filter(\.onPeriod).count : nil,
                           sickDays: includeSick ? inWindow.filter(\.isSick).count : nil, current: goals,
                           pace: pace, measures: measureFacts, targetGapKg: gap, useLb: useLb)
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

        // Estimated maintenance (TDEE): from the logs when they have built one, else the formula as a starting point.
        let maintenance = s.estimatedMaintenance
        let trendMaintenance = s.maintenanceSource == .trend && (s.maintenanceConfidence ?? .low) >= .medium
        if let m = maintenance {
            let compare = goalCal.map { g -> String in
                let pct = Int((abs(1 - Double(g) / Double(m)) * 100).rounded())
                return pct < 2 ? ", so your goal of \(fmt(g)) is about at maintenance" : ", so your goal of \(fmt(g)) is about \(pct)% \(g < m ? "below" : "above") it"
            } ?? ""
            if s.maintenanceSource == .trend {
                evidence.append("Your estimated maintenance is about \(fmt(m)) kcal a day, worked out from your weight trend and what you ate"
                                + (s.maintenanceStatus == .updating ? "" : " (held from earlier, because recent logs are thin)") + compare + ".")
            } else {
                evidence.append("A formula estimate from your height, age, sex and activity puts maintenance near \(fmt(m)) kcal a day" + compare
                                + ". It is a starting point until your own logs build an estimate.")
            }
            if s.maintenanceSource == .trend, let f = s.formulaMaintenance, Double(abs(f - m)) > 0.25 * Double(f) {
                cautions.append("The estimate from your logs (\(fmt(m))) and the formula (\(fmt(f))) are far apart. That can mean logged intake or weigh-ins are incomplete.")
            }
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
        // Objective context from Health. It can add a caution and soften "good" recovery, but never changes training on its own.
        if let m = s.avgSleepMinutes {
            evidence.append(String(format: "Health recorded an average of %.1f hours asleep on %d %@.", Double(m) / 60, s.sleepNights, s.sleepNights == 1 ? "night" : "nights"))
        }
        if let hrv = s.avgRestingHR {
            var line = "Resting heart rate averaged \(hrv) bpm" + (s.restingHRChange.map { abs($0) >= 1 ? String(format: " (%+.0f on the week before)", $0) : "" } ?? "")
            if let v = s.avgHRV { line += " and HRV \(v) ms" + (s.hrvChangePercent.map { abs($0) >= 5 ? String(format: " (%+.0f%%)", $0) : "" } ?? "") }
            evidence.append(line + ".")
        }
        if (s.restingHRChange ?? 0) >= 5, (s.hrvChangePercent ?? 0) <= -15 {
            cautions.append("Resting heart rate is up and HRV is down on the week before. That can go with poor recovery or illness. It is context, not a verdict on training.")
            if recovery == .good { recovery = .mixed }
        }
        if sick > 0 { evidence.append("You were sick on \(sick) \(sick == 1 ? "day" : "days") this week.") }
        if let p = s.periodDays, p > 0 { evidence.append("\(p) period \(p == 1 ? "day" : "days") this week, which can hold water and blur the scale.") }

        // Calories: only change when the evidence says the target (not the effort) is off.
        var delta = 0
        let need: Int = rate == .aboveBand ? -1 : (rate == .belowBand ? 1 : 0)
        let lowTarget = baseCal < lowCalorieThreshold
            || (maintenance.map { Double(baseCal) < (1 - maxDeficitFromMaintenance) * Double($0) } == true && (trendMaintenance || s.maintenanceSource == .formula))
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
                var size = step(s.kind, need: need, pct: s.weightChangePercentPerWeek ?? 0, band: band)
                // With a trustworthy maintenance estimate, size the move by where the target would need to be for the pace
                // this campaign aims for, and never by more than the weekly limit.
                if trendMaintenance, let m = maintenance, let tw = s.trendWeightKg {
                    let aimKgPerWeek = (band.lowerBound + band.upperBound) / 2 / 100 * tw
                    let wanted = Double(m) + aimKgPerWeek * Maintenance.kcalPerKgPerWeekAsDaily
                    let gap = wanted - Double(baseCal)
                    if gap * Double(need) > 0 {
                        size = min(size, max(50, Int((abs(gap) / 50).rounded()) * 50))
                        evidence.append("To reach about \(String(format: "%+.1f", (band.lowerBound + band.upperBound) / 2))% a week from that maintenance, a target near \(fmt(Int((wanted / 10).rounded()) * 10)) would do it. Moving \(size) now keeps the change gradual.")
                    } else {
                        size = 0
                        cautions.append("Your estimated maintenance suggests your target already sits where this campaign's pace would put it, so the scale and the estimate disagree. The target stays until more data settles it.")
                    }
                }
                delta = need * size
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

        // Pace. The conservative move is the one worked out above. The aggressive pace aims for the faster end of what the campaign allows,
        // sized from estimated maintenance, held to the same rails (calorie floor, no more than a quarter below maintenance) and offered only
        // when the data is reliable and nothing (illness, strain, hunger) argues against it. It never moves less than the conservative one.
        let conservativeDelta = delta
        var aggressiveDelta: Int?
        var aggressiveNote: String?
        let blocked: String? = sick > 0 ? "you were sick" : (strain ? "recovery looks strained" : ((s.kind == .cut && (hunger ?? 0) >= 4.2) ? "hunger is high" : nil))
        if s.kind == .maintenance {
            aggressiveNote = "Maintenance has one pace: calories stay near maintenance."
        } else if conf.forCalories < .medium {
            aggressiveNote = "A faster option needs more weigh-ins and calorie logs first."
        } else if let m = maintenance, trendMaintenance || s.maintenanceSource == .formula, let tw = s.trendWeightKg {
            if let b = blocked {
                aggressiveNote = "A faster pace isn't offered because \(b)."
            } else if (s.kind == .cut && rate == .belowBand) || (s.kind == .bulk && rate == .aboveBand) {
                aggressiveNote = "Your weight is already moving faster than a \(s.kind.title.lowercased()) aims for, so there is no faster option."
            } else if s.kind == .cut && lowTarget {
                aggressiveNote = "Your calorie target is already low, so there is no faster option."
            } else {
                let aimPct = s.kind == .cut ? -0.9 : 0.45
                let wanted = Double(m) + aimPct / 100 * tw * Maintenance.kcalPerKgPerWeekAsDaily
                var target = Int((wanted / 10).rounded()) * 10
                if s.kind == .cut { target = max(target, Int(0.75 * Double(m)), hardCalorieFloor) } else { target = min(target, Int(1.2 * Double(m))) }
                var move = min(max(target - baseCal, -aggressiveStepLimit), aggressiveStepLimit)
                move = s.kind == .cut ? min(move, conservativeDelta) : max(move, conservativeDelta)
                if move != conservativeDelta { aggressiveDelta = move }
                else { aggressiveNote = "Your target already sits where a faster pace would put it, so both options are the same." }
            }
        } else {
            aggressiveNote = "A faster option needs an estimate of your maintenance calories first. Add your details in Settings → About you, or keep logging."
        }
        let chosen = s.pace == .aggressive ? (aggressiveDelta ?? conservativeDelta) : conservativeDelta
        let lo = min(baseCal, baseCal + chosen), hi = max(baseCal, baseCal + chosen)
        return Assessment(confidence: conf, rate: rate, intake: intake, adherence: adherence, recovery: recovery,
                          baseCalories: baseCal, baseSteps: baseSteps, baseWorkouts: baseWork, caloriesDelta: chosen, stepsTarget: steps,
                          workoutsDelta: workoutsDelta, allowedCalories: lo...hi,
                          allowedSteps: min(baseSteps, steps ?? baseSteps)...baseSteps,
                          allowedWorkouts: max(baseWork + workoutsDelta, 0)...baseWork,
                          evidence: evidence, cautions: cautions, needMoreData: needMore,
                          conservativeDelta: conservativeDelta, aggressiveDelta: aggressiveDelta, aggressiveNote: aggressiveNote)
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
        var p = PlanSuggestion(caloriesPerDay: cal, proteinG: m.protein, carbsG: m.carbs, fatG: m.fat, steps: st, workoutDays: wk,
                               waterMl: s.current.waterDailyMl, confidence: overall, metricConfidence: a.confidence, headline: head,
                               evidence: evidence, cautions: a.cautions, needMoreData: a.needMoreData, note: note, source: source)
        p.pace = s.pace
        if let mt = s.estimatedMaintenance { p.expectedKgPerWeek = Double(cal - mt) / Maintenance.kcalPerKgPerWeekAsDaily }
        p.why = why(s, a, calories: cal, steps: st, workouts: wk)
        return p
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
