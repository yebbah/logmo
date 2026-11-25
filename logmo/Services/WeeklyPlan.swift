import Foundation

/// How far a campaign's weekly plan reaches, and which weeks may still be changed.
struct PlanBounds: Equatable {
    var first: Date                    // Monday of the week the campaign starts
    var last: Date                     // Monday of the last week shown
    var editable: ClosedRange<Date>?   // this week up to four weeks ahead, inside the campaign; nil once it has ended
}

/// What the Dashboard should ask about the weekly plan, if anything.
enum PlanPrompt: Equatable {
    case none
    case setGoals                      // the campaign has no goals at all
    case carriedOver(week: Date)       // this week's goals are only last week's, not confirmed
    case planNext(week: Date)          // it's Sunday and next week isn't set
}

/// One week of a campaign's plan, with how it went.
struct WeekPlanRow: Identifiable, Equatable {
    enum Phase: Equatable { case past, current, future }
    var weekStart: Date
    var phase: Phase
    var goals: GoalSet?                // the goals that apply: its own, or carried over from the week before
    var previous: GoalSet?             // the week before's, to highlight what changed
    var isSet: Bool                    // the user set or confirmed this week's goals
    var days: Int                      // days of this week inside the campaign, up to today
    var compliedDays: Int
    var strip: [Metrics.DayCompliance]
    var outcome: WeekOutcome           // all the week's weekly goals together
    var reason: String?                // why a missed week was missed
    var trendKg: Double? = nil         // the weight trend at the end of the week (so far, for the current week); nil for a future week or no trend yet
    var trendChangeKg: Double? = nil   // from the end of the week before; nil is N/A (nothing before it, or the campaign restarted the trend)
    var trendChangePercent: Double? = nil
    var id: Date { weekStart }
}

enum PlanRules {
    private static func addDays(_ n: Int, to d: Date, _ cal: Calendar) -> Date { cal.date(byAdding: .day, value: n, to: d)! }

    static func bounds(_ c: CampaignInfo, today: Date, calendar cal: Calendar = .current) -> PlanBounds {
        let thisWeek = Metrics.weekStart(of: today, calendar: cal)
        let first = Metrics.weekStart(of: c.start, calendar: cal)
        let campaignLast = (c.end ?? CampaignRules.plannedEnd(c, calendar: cal)).map { Metrics.weekStart(of: $0, calendar: cal) }
        let from = max(thisWeek, first)
        if let cl = campaignLast, from > cl {                       // the campaign is over: every week is past
            return PlanBounds(first: first, last: cl, editable: nil)
        }
        var to = addDays(28, to: from, cal)                          // four weeks ahead
        if let cl = campaignLast { to = min(to, cl) }
        return PlanBounds(first: first, last: to, editable: from...max(to, from))
    }

    /// The effective goals for a week: the latest set at or before it.
    static func effective(_ byWeek: [Date: GoalSet], at week: Date) -> GoalSet? {
        guard let k = byWeek.keys.filter({ $0 <= week }).max() else { return nil }
        return byWeek[k]
    }

    /// Following weeks (up to `count`) that a "repeat" gives the same goals: every one inside the editable range,
    /// including weeks already set or confirmed (they are replaced, and the editor says how many).
    static func weeksToFill(after week: Date, count: Int, bounds b: PlanBounds,
                            calendar cal: Calendar = .current) -> [Date] {
        guard let e = b.editable, count > 0 else { return [] }
        return (1...count).map { addDays(7 * $0, to: week, cal) }.filter { e.contains($0) }
    }

    /// How many following weeks exist inside the editable range after `week`.
    static func followingWeeks(after week: Date, bounds b: PlanBounds, calendar cal: Calendar = .current) -> Int {
        guard let e = b.editable else { return 0 }
        let n = (cal.dateComponents([.day], from: week, to: e.upperBound).day ?? 0) / 7
        return max(0, min(4, n))
    }

    static func prompt(_ c: CampaignInfo, hasAnyGoals: Bool, explicit: Set<Date>, today: Date,
                       calendar cal: Calendar = .current) -> PlanPrompt {
        guard CampaignRules.contains(c, day: today, calendar: cal) else { return .none }
        if !hasAnyGoals { return .setGoals }
        let thisWeek = Metrics.weekStart(of: today, calendar: cal)
        let b = bounds(c, today: today, calendar: cal)
        if cal.component(.weekday, from: today) == 1 {              // Sunday: plan the week ahead
            let next = addDays(7, to: thisWeek, cal)
            return (b.editable?.contains(next) == true && !explicit.contains(next)) ? .planNext(week: next) : .none
        }
        return explicit.contains(thisWeek) ? .none : .carriedOver(week: thisWeek)
    }
}

extension Insights {
    /// Every week of a campaign's plan, oldest first, each with its goals and, once it has begun, how it went.
    /// `weeks` is this campaign's own goals by Monday; `explicit` the Mondays the user set or confirmed;
    /// `timeline` the all-campaign goals used for judging each day.
    static func weeklyPlan(_ c: CampaignInfo, snaps: [DaySnapshot], weeks: [Date: GoalSet], explicit: Set<Date>,
                           timeline: GoalTimeline, required: Set<Tracker>, today: Date, trend: [TrendPoint] = [],
                           calendar cal: Calendar = .current) -> [WeekPlanRow] {
        let t = cal.startOfDay(for: today)
        let b = PlanRules.bounds(c, today: today, calendar: cal)
        let campaignEnd = c.end
        var rows: [WeekPlanRow] = []
        // Each week's weight trend and its change from the week before (the Dashboard's weekly rate of change), kept with the week as history.
        let trendRows = Dictionary(Metrics.weeklyTrendRows(trend, from: b.first, through: t, limit: 520, calendar: cal).map { ($0.weekStart, $0) },
                                   uniquingKeysWith: { a, _ in a })
        var ws = b.first
        while ws <= b.last {
            let weekEnd = cal.date(byAdding: .day, value: 6, to: ws)!
            let phase: WeekPlanRow.Phase = weekEnd < t ? .past : (ws <= t ? .current : .future)
            let goals = PlanRules.effective(weeks, at: ws)
            let prev = PlanRules.effective(weeks, at: cal.date(byAdding: .day, value: -7, to: ws)!)

            // The days of this week that belong to the campaign and have happened.
            let from = max(ws, c.start)
            let to = min(weekEnd, campaignEnd ?? weekEnd, t)
            let strip: [Metrics.DayCompliance] = from <= to
                ? Metrics.complianceStrip(snaps, from: from, to: to, today: today, required: required, timeline: timeline, calendar: cal)
                : []

            var outcome: WeekOutcome = .noGoal
            var reason: String?
            if let goals, goals.hasWeeklyGoals {
                outcome = phase == .future ? .inProgress : Metrics.weeklyOutcome(snaps, weekStart: ws, goals: goals, today: today, calendar: cal)
                if outcome == .missed { reason = missReason(snaps, ws, goals, today, cal) }
            }
            let tr = phase == .future ? nil : trendRows[ws]
            rows.append(WeekPlanRow(weekStart: ws, phase: phase, goals: goals, previous: prev, isSet: explicit.contains(ws),
                                    days: strip.count, compliedDays: strip.filter { $0 == .complied }.count,
                                    strip: strip, outcome: outcome, reason: reason,
                                    trendKg: tr?.trendKg, trendChangeKg: tr?.changeKg, trendChangePercent: tr?.changePercent))
            ws = cal.date(byAdding: .day, value: 7, to: ws)!
        }
        return rows
    }

    /// The first reason a week's weekly goals were missed, in words.
    private static func missReason(_ snaps: [DaySnapshot], _ ws: Date, _ g: GoalSet, _ today: Date, _ cal: Calendar) -> String? {
        func n(_ v: Double?) -> String { v.map { Int($0.rounded()).formatted() } ?? "—" }
        if g.caloriesWeekly != nil {
            let s = Metrics.weekStatus(snaps, weekStart: ws, goals: g, today: today, calendar: cal)
            if s.outcome == .missed {
                return s.daysWithCalories < 7 ? "calories not logged on every day"
                    : "calories averaged \(n(s.average)) against \(n(s.dailyTarget))"
            }
        }
        if g.weeklyAverageStepsGoal != nil {
            let s = Metrics.stepsWeekStatus(snaps, weekStart: ws, goals: g, today: today, calendar: cal)
            if s.outcome == .missed {
                return s.daysWithCalories < 7 ? "steps not logged on every day" : "steps averaged \(n(s.average)) against \(n(s.dailyTarget))"
            }
        }
        if g.workoutDaysWeekly != nil {
            let w = Metrics.workoutWeek(snaps, weekStart: ws, goals: g, today: today, calendar: cal)
            if w.outcome == .missed { return "\(w.done) of \(w.target ?? 0) workouts" }
        }
        return nil
    }
}
