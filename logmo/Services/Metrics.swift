import Foundation

/// The things a user can log in a day.
enum Tracker: String, CaseIterable, Identifiable {
    case weight, food, water, steps, checkIn
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weight: "Weight"
        case .food: "Food"
        case .water: "Water"
        case .steps: "Steps"
        case .checkIn: "Check-in"
        }
    }
}

/// Plain-value view of one day's log. Keeps the maths independent of SwiftData.
struct DaySnapshot: Equatable {
    var date: Date                  // any time on the day; normalised by callers
    var weightKg: Double?
    var logged: Set<Tracker>        // anything entered for that tracker
    var complete: Set<Tracker> = [] // every field of that tracker entered
    var calories: Int? = nil
    var proteinG: Int? = nil
    var waterMl: Int? = nil
    var steps: Int? = nil
    var ratings: [String: Int] = [:]
}

// MARK: - Goals

/// Goals for one week. Calories are a weekly total; the rest are per day.
struct GoalSet: Equatable {
    var caloriesWeekly: Int?
    var caloriesAtOrUnder: Bool = true   // false = the weekly total should reach the goal
    var proteinDaily: Int?
    var stepsDaily: Int?
    var waterDailyMl: Int?
    var hasDailyGoals: Bool { proteinDaily != nil || stepsDaily != nil || waterDailyMl != nil }
}

/// Goals keyed by the Monday that starts their week. A week without its own goals
/// inherits the most recent earlier ones.
struct GoalTimeline: Equatable {
    var byWeek: [Date: GoalSet] = [:]
    func goals(forWeekStarting ws: Date) -> GoalSet? {
        guard let key = byWeek.keys.filter({ $0 <= ws }).max() else { return nil }
        return byWeek[key]
    }
    func inheritedFrom(_ ws: Date) -> Date? {
        guard byWeek[ws] == nil else { return nil }
        return byWeek.keys.filter { $0 <= ws }.max()
    }
}

/// nil = no goal set for that metric. A goal with no value logged counts as not met.
struct DayGoalStatus: Equatable {
    var protein: Bool?
    var steps: Bool?
    var water: Bool?
    var allMet: Bool {
        let g = [protein, steps, water].compactMap { $0 }
        return !g.isEmpty && g.allSatisfy { $0 }
    }
}

enum WeekOutcome: Equatable { case noGoal, inProgress, met, missed }

struct WeekStatus: Equatable {
    var weekStart: Date
    var goal: Int?
    var atOrUnder: Bool
    var total: Int
    var daysWithCalories: Int
    var outcome: WeekOutcome
    /// Average daily calories over the days that have calories logged.
    var average: Double? { daysWithCalories == 0 ? nil : Double(total) / Double(daysWithCalories) }
    /// The weekly goal expressed per day (goal ÷ 7): what the average is compared against.
    var dailyTarget: Double? { goal.map { Double($0) / 7 } }
}

// MARK: - Series

struct TrendPoint: Identifiable, Equatable {
    var date: Date
    var weightKg: Double?   // measured, nil when no weigh-in that day
    var trendKg: Double     // smoothed
    var id: Date { date }
}

struct ValuePoint: Identifiable, Equatable {
    var date: Date
    var value: Double?
    var trend: Double
    var id: Date { date }
}

struct Compliance: Equatable {
    var windowDays: Int                 // days evaluated; today is left out while still in progress
    var compliedDays: Int
    var perTracker: [Tracker: Int]      // days each tracker was fully logged
    var goalDays: Int                   // days whose daily goals were all met
    var rate: Double { windowDays == 0 ? 0 : Double(compliedDays) / Double(windowDays) }
    func rate(for t: Tracker) -> Double {
        windowDays == 0 ? 0 : Double(perTracker[t, default: 0]) / Double(windowDays)
    }
}

enum Metrics {
    /// Workbook default: 16-day smoothing, alpha = 2 / (N + 1) ≈ 0.1176.
    static func alpha(forDays n: Int) -> Double { 2.0 / Double(n + 1) }

    private static func byDay(_ days: [DaySnapshot], _ cal: Calendar) -> [Date: DaySnapshot] {
        var out: [Date: DaySnapshot] = [:]
        for d in days { out[cal.startOfDay(for: d.date)] = d }
        return out
    }

    private static func addDays(_ n: Int, to d: Date, _ cal: Calendar) -> Date {
        cal.date(byAdding: .day, value: n, to: d)!
    }

    /// Monday of the week containing `date` (weeks run Monday to Sunday).
    static func weekStart(of date: Date, calendar cal: Calendar = .current) -> Date {
        let d = cal.startOfDay(for: date)
        let offset = (cal.component(.weekday, from: d) + 5) % 7   // Mon = 0 … Sun = 6
        return addDays(-offset, to: d, cal)
    }

    // MARK: Streaks

    /// Current and longest run of consecutive qualifying days. Today not qualifying
    /// *yet* does not break the current streak.
    static func streak(of qualifying: Set<Date>, today: Date, calendar cal: Calendar = .current)
        -> (current: Int, longest: Int)
    {
        let t = cal.startOfDay(for: today)
        var current = 0
        var cursor = qualifying.contains(t) ? t : addDays(-1, to: t, cal)
        while qualifying.contains(cursor) {
            current += 1
            cursor = addDays(-1, to: cursor, cal)
        }
        var longest = 0, run = 0
        var prev: Date?
        for d in qualifying.sorted() {
            if let p = prev, addDays(1, to: p, cal) == d { run += 1 } else { run = 1 }
            longest = max(longest, run)
            prev = d
        }
        return (current, longest)
    }

    /// Logging streak: days with at least one tracker logged.
    static func streak(_ days: [DaySnapshot], today: Date, calendar cal: Calendar = .current)
        -> (current: Int, longest: Int)
    {
        let set = Set(days.filter { !$0.logged.isEmpty }.map { cal.startOfDay(for: $0.date) })
        return streak(of: set, today: today, calendar: cal)
    }

    /// Daily-goal streak: days on which every daily goal that was set was met.
    static func goalStreak(_ days: [DaySnapshot], timeline: GoalTimeline, today: Date,
                           calendar cal: Calendar = .current) -> (current: Int, longest: Int) {
        var set = Set<Date>()
        for s in days {
            let d = cal.startOfDay(for: s.date)
            let goals = timeline.goals(forWeekStarting: weekStart(of: d, calendar: cal))
            if dayGoalStatus(s, goals: goals).allMet { set.insert(d) }
        }
        return streak(of: set, today: today, calendar: cal)
    }

    /// Weekly-goal streak: consecutive *finished* weeks whose calorie goal was met.
    /// The week in progress never breaks or extends the streak.
    static func weeklyStreak(_ days: [DaySnapshot], timeline: GoalTimeline, today: Date,
                             calendar cal: Calendar = .current) -> (current: Int, longest: Int) {
        guard let first = timeline.byWeek.keys.min() else { return (0, 0) }
        let thisWeek = weekStart(of: today, calendar: cal)
        var results: [Bool] = []
        var ws = first
        while ws < thisWeek {
            let st = weekStatus(days, weekStart: ws, goals: timeline.goals(forWeekStarting: ws),
                                today: today, calendar: cal)
            results.append(st.outcome == .met)
            ws = addDays(7, to: ws, cal)
        }
        var current = 0
        for r in results.reversed() { if r { current += 1 } else { break } }
        var longest = 0, run = 0
        for r in results { run = r ? run + 1 : 0; longest = max(longest, run) }
        return (current, longest)
    }

    // MARK: Goal evaluation

    /// Protein, steps and water are met at or above the goal.
    static func dayGoalStatus(_ s: DaySnapshot?, goals: GoalSet?) -> DayGoalStatus {
        guard let goals else { return DayGoalStatus() }
        func check(_ value: Int?, _ goal: Int?) -> Bool? {
            guard let goal else { return nil }
            guard let value else { return false }
            return value >= goal
        }
        return DayGoalStatus(protein: check(s?.proteinG, goals.proteinDaily),
                             steps: check(s?.steps, goals.stepsDaily),
                             water: check(s?.waterMl, goals.waterDailyMl))
    }

    /// Average daily calories (over logged days) against the goal ÷ 7, compared as
    /// `total × 7` vs `goal × days` so no rounding is involved.
    static func calorieAverageOK(total: Int, days n: Int, goal: Int, atOrUnder: Bool) -> Bool {
        guard n > 0 else { return false }
        return atOrUnder ? total * 7 <= goal * n : total * 7 >= goal * n
    }

    /// Is the week's average calorie intake on target? nil when there is no calorie goal.
    /// A week in progress is judged on the days logged so far; a finished week on the whole week.
    static func weekCalorieOK(_ map: [Date: DaySnapshot], weekStart ws: Date, goals: GoalSet?,
                              calendar cal: Calendar = .current) -> Bool? {
        guard let goals, let goal = goals.caloriesWeekly else { return nil }
        var total = 0, n = 0
        for i in 0..<7 {
            if let c = map[addDays(i, to: ws, cal)]?.calories { total += c; n += 1 }
        }
        return calorieAverageOK(total: total, days: n, goal: goal, atOrUnder: goals.caloriesAtOrUnder)
    }

    /// Weekly calories, judged on the week's average. A finished week only counts as met
    /// if calories were logged on all seven days, so a few logged days can't stand in for a week.
    static func weekStatus(_ days: [DaySnapshot], weekStart ws: Date, goals: GoalSet?, today: Date,
                           calendar cal: Calendar = .current) -> WeekStatus {
        let map = byDay(days, cal)
        var total = 0, n = 0
        for i in 0..<7 {
            if let c = map[addDays(i, to: ws, cal)]?.calories { total += c; n += 1 }
        }
        let under = goals?.caloriesAtOrUnder ?? true
        guard let goal = goals?.caloriesWeekly else {
            return WeekStatus(weekStart: ws, goal: nil, atOrUnder: under, total: total,
                              daysWithCalories: n, outcome: .noGoal)
        }
        let finished = cal.startOfDay(for: today) > addDays(6, to: ws, cal)
        let outcome: WeekOutcome
        if finished {
            outcome = (n == 7 && calorieAverageOK(total: total, days: n, goal: goal, atOrUnder: under)) ? .met : .missed
        } else if under && total > goal {
            outcome = .missed
        } else {
            outcome = .inProgress
        }
        return WeekStatus(weekStart: ws, goal: goal, atOrUnder: under, total: total,
                          daysWithCalories: n, outcome: outcome)
    }

    // MARK: Compliance

    /// Complied = every required tracker fully logged, every daily goal met, and (when a
    /// calorie goal exists) the week's average calories on target (`calorieOK`).
    static func dayComplied(_ s: DaySnapshot?, required: Set<Tracker>, goals: GoalSet?,
                            calorieOK: Bool? = nil) -> Bool {
        guard let s, !s.logged.isEmpty else { return false }
        guard required.isSubset(of: s.complete) else { return false }
        if calorieOK == false { return false }
        if goals?.hasDailyGoals == true { return dayGoalStatus(s, goals: goals).allMet }
        return true
    }

    /// Over the last `windowDays` days ending today. Today is left out of the
    /// denominator until it is complied, so an unfinished day isn't counted as a miss.
    static func compliance(_ days: [DaySnapshot], today: Date, windowDays: Int,
                           required: Set<Tracker>, timeline: GoalTimeline,
                           calendar cal: Calendar = .current) -> Compliance {
        let map = byDay(days, cal)
        let t = cal.startOfDay(for: today)
        var evaluated = 0, complied = 0, goalDays = 0
        var per: [Tracker: Int] = [:]
        for offset in 0..<windowDays {
            let d = addDays(-offset, to: t, cal)
            let s = map[d]
            let ws = weekStart(of: d, calendar: cal)
            let goals = timeline.goals(forWeekStarting: ws)
            let ok = dayComplied(s, required: required, goals: goals,
                                 calorieOK: weekCalorieOK(map, weekStart: ws, goals: goals, calendar: cal))
            if offset == 0 && !ok { continue }
            evaluated += 1
            if ok { complied += 1 }
            if dayGoalStatus(s, goals: goals).allMet { goalDays += 1 }
            for tr in s?.complete ?? [] { per[tr, default: 0] += 1 }
        }
        return Compliance(windowDays: evaluated, compliedDays: complied, perTracker: per, goalDays: goalDays)
    }

    // MARK: Trends

    /// Exponential smoothing over a sparse daily series. Missing days carry the previous
    /// value forward (never treated as zero). Runs from the first value to `through`.
    static func smoothed(_ values: [Date: Double], through: Date, smoothingDays: Int,
                         calendar cal: Calendar = .current) -> [ValuePoint] {
        guard let first = values.keys.min() else { return [] }
        let a = alpha(forDays: smoothingDays)
        let end = max(cal.startOfDay(for: through), first)
        var out: [ValuePoint] = []
        var trend: Double?
        var cursor = first
        while cursor <= end {
            let v = values[cursor]
            if let v { trend = trend.map { a * v + (1 - a) * $0 } ?? v }
            if let trend { out.append(ValuePoint(date: cursor, value: v, trend: trend)) }
            cursor = addDays(1, to: cursor, cal)
        }
        return out
    }

    static func weightTrend(_ days: [DaySnapshot], through: Date, smoothingDays: Int = 16,
                            calendar cal: Calendar = .current) -> [TrendPoint] {
        var vals: [Date: Double] = [:]
        for s in days { if let w = s.weightKg { vals[cal.startOfDay(for: s.date)] = w } }
        return smoothed(vals, through: through, smoothingDays: smoothingDays, calendar: cal)
            .map { TrendPoint(date: $0.date, weightKg: $0.value, trendKg: $0.trend) }
    }

    /// Smoothed trend for one biofeedback rating (1–5).
    static func ratingTrend(_ days: [DaySnapshot], rating: String, through: Date,
                            smoothingDays: Int = 7, calendar cal: Calendar = .current) -> [ValuePoint] {
        var vals: [Date: Double] = [:]
        for s in days { if let r = s.ratings[rating] { vals[cal.startOfDay(for: s.date)] = Double(r) } }
        return smoothed(vals, through: through, smoothingDays: smoothingDays, calendar: cal)
    }

    /// Change in trend weight versus `days` days earlier; nil until enough history exists.
    static func trendChange(_ trend: [TrendPoint], overDays days: Int = 7,
                            calendar cal: Calendar = .current) -> Double? {
        guard let last = trend.last,
              let target = cal.date(byAdding: .day, value: -days, to: last.date),
              let past = trend.first(where: { $0.date == target }) else { return nil }
        return last.trendKg - past.trendKg
    }
}

enum WeightUnit: String, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }
    func fromKg(_ kg: Double) -> Double { self == .kg ? kg : kg * 2.2046226218 }
    func toKg(_ v: Double) -> Double { self == .kg ? v : v / 2.2046226218 }
}
