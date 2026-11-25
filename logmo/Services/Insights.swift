import Foundation

enum BetterWhen { case higher, lower, neutral }

extension Rating {
    /// Which direction is better, from the confirmed anchors. Appetite has no better
    /// direction: whether a big appetite is good depends on the goal.
    var betterWhen: BetterWhen {
        switch self {
        case .sleep, .performance: .higher
        case .fatigue, .stress, .hunger, .soreness: .lower
        case .appetite: .neutral
        }
    }

    var betterNote: String {
        switch betterWhen {
        case .higher: "higher is better"
        case .lower: "lower is better"
        case .neutral: "no better direction"
        }
    }
}

struct Averages: Equatable {
    var calories: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var waterMl: Double?
    var steps: Double?
}

struct RatePoint: Identifiable, Equatable {
    var date: Date
    var kgPerWeek: Double       // trend weight now minus trend weight 7 days earlier
    var id: Date { date }
}

struct CampaignSummary: Equatable {
    var days: Int                  // days from the start to the end (or today), inclusive
    var daysLogged: Int
    var startTrendKg: Double?
    var endTrendKg: Double?
    var averages: Averages
    var changeKg: Double? {
        guard let a = startTrendKg, let b = endTrendKg else { return nil }
        return b - a
    }
}

enum Insights {
    /// Results of a campaign: its trend weight at the start and end, and averages over its days.
    /// The trend is computed over *all* data and only read here, so it doesn't restart per campaign.
    static func campaignSummary(_ c: CampaignInfo, snaps: [DaySnapshot], trend: [TrendPoint], today: Date,
                                calendar cal: Calendar = .current) -> CampaignSummary {
        let end = min(c.end ?? today, cal.startOfDay(for: today))
        let inRange = trend.filter { $0.date >= c.start && $0.date <= end }
        let rows = snaps.filter {
            let d = cal.startOfDay(for: $0.date)
            return d >= c.start && d <= end && !$0.logged.isEmpty
        }
        let span = (cal.dateComponents([.day], from: c.start, to: end).day ?? 0) + 1
        return CampaignSummary(days: max(span, 0), daysLogged: rows.count,
                               startTrendKg: inRange.first?.trendKg, endTrendKg: inRange.last?.trendKg,
                               averages: averages(snaps, from: c.start, to: end, calendar: cal))
    }

    /// Every day from `from` to `to`, inclusive.
    static func days(from: Date, to: Date, calendar cal: Calendar = .current) -> [Date] {
        var out: [Date] = []
        var d = cal.startOfDay(for: from)
        let end = cal.startOfDay(for: to)
        while d <= end {
            out.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }

    private static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// Averages over the days that have a value. Missing days are left out, never counted as zero.
    static func averages(_ snaps: [DaySnapshot], from: Date, to: Date, calendar cal: Calendar = .current) -> Averages {
        let range = days(from: from, to: to, calendar: cal)
        let map = Dictionary(snaps.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let rows = range.compactMap { map[$0] }
        return Averages(calories: mean(rows.compactMap { $0.calories.map(Double.init) }),
                        proteinG: mean(rows.compactMap { $0.proteinG.map(Double.init) }),
                        carbsG: mean(rows.compactMap { $0.carbsG.map(Double.init) }),
                        fatG: mean(rows.compactMap { $0.fatG.map(Double.init) }),
                        waterMl: mean(rows.compactMap { $0.waterMl.map(Double.init) }),
                        steps: mean(rows.compactMap { $0.steps.map(Double.init) }))
    }

    /// One entry per day; nil where the rating wasn't logged.
    static func ratingSeries(_ snaps: [DaySnapshot], rating: String, from: Date, to: Date,
                             calendar cal: Calendar = .current) -> [(date: Date, value: Int?)] {
        let map = Dictionary(snaps.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        return days(from: from, to: to, calendar: cal).map { ($0, map[$0]?.ratings[rating]) }
    }

    static func average(_ values: [Int?]) -> Double? { mean(values.compactMap { $0.map(Double.init) }) }

    /// Days in range with a protein goal: how many reached it. A day with no protein logged
    /// counts as missed. Days without a protein goal are left out.
    static func proteinDays(_ snaps: [DaySnapshot], timeline: GoalTimeline, from: Date, to: Date,
                            calendar cal: Calendar = .current) -> (hit: Int, missed: Int) {
        let map = Dictionary(snaps.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        var hit = 0, missed = 0
        for d in days(from: from, to: to, calendar: cal) {
            guard let goal = timeline.goals(forDay: d, calendar: cal)?.proteinDaily
            else { continue }
            if let p = map[d]?.proteinG, p >= goal { hit += 1 } else { missed += 1 }
        }
        return (hit, missed)
    }

    /// Weekly rate of change of the trend weight: today's trend minus the trend 7 days earlier.
    static func rateOfChange(_ trend: [TrendPoint], overDays n: Int = 7, calendar cal: Calendar = .current) -> [RatePoint] {
        let byDate = Dictionary(trend.map { ($0.date, $0.trendKg) }, uniquingKeysWith: { a, _ in a })
        return trend.compactMap { p in
            guard let prev = cal.date(byAdding: .day, value: -n, to: p.date), let before = byDate[prev] else { return nil }
            return RatePoint(date: p.date, kgPerWeek: (p.trendKg - before) * 7 / Double(n))
        }
    }
}


// MARK: - A campaign's look back

struct CampaignReport {
    var days: Int                                   // days from the start to the end (or today), inclusive
    var daysLogged: Int                             // days with anything logged
    var daysWeighed: Int
    var startTrendKg: Double?
    var endTrendKg: Double?
    var avgWeeklyChangeKg: Double?                  // change per week across the campaign
    var fastestWeekKg: Double?                      // the largest 7-day trend change (signed)
    var compliance: Compliance
    var strip: [Metrics.DayCompliance] = []         // one entry per day, oldest first
    var dailyGoalDaysMet = 0, dailyGoalDays = 0     // days whose daily goals were met, out of days with daily goals
    var weeklyGoalsMet = 0, weeklyGoals = 0         // finished weeks whose goals were met, out of those with goals
    var workoutsPerWeek: Double?                    // average workout days a week
    var goalsAtEnd: GoalSet?
    var averages: Averages
    var ratingAverages: [String: Double]
    var changeKg: Double? {
        guard let a = startTrendKg, let b = endTrendKg else { return nil }
        return b - a
    }
    var started: Bool { days > 0 }
}

extension Insights {
    /// Days with daily goals met, and finished weeks (owned by this campaign) whose weekly goals were met.
    static func goalResults(_ snaps: [DaySnapshot], timeline: GoalTimeline, campaign c: CampaignInfo, today: Date,
                            calendar cal: Calendar = .current)
        -> (dayMet: Int, dayTotal: Int, weekMet: Int, weekTotal: Int, atEnd: GoalSet?)
    {
        let t = cal.startOfDay(for: today)
        let end = min(c.end ?? t, t)
        let map = Dictionary(snaps.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        var dayMet = 0, dayTotal = 0, weekMet = 0, weekTotal = 0
        for d in days(from: c.start, to: end, calendar: cal) {
            let goals = timeline.goals(forDay: d, calendar: cal)
            guard goals?.hasDailyGoals == true else { continue }
            dayTotal += 1
            if Metrics.dayGoalStatus(map[d], goals: goals).allMet { dayMet += 1 }
        }
        var ws = Metrics.weekStart(of: c.start, calendar: cal)
        while cal.date(byAdding: .day, value: 6, to: ws)! <= end {
            if timeline.book?.owner(ofWeek: ws, calendar: cal)?.id == c.id,
               let goals = timeline.goals(forWeekStarting: ws, calendar: cal), goals.hasWeeklyGoals {
                weekTotal += 1
                if Metrics.weeklyOutcome(snaps, weekStart: ws, goals: goals, today: today, calendar: cal) == .met { weekMet += 1 }
            }
            ws = cal.date(byAdding: .day, value: 7, to: ws)!
        }
        return (dayMet, dayTotal, weekMet, weekTotal, end >= c.start ? timeline.goals(forDay: end, calendar: cal) : nil)
    }

    /// Everything the Campaigns tab shows about one campaign. The trend is the one computed over all
    /// data, so a campaign's start and end weights come from a series that doesn't restart.
    static func campaignReport(_ c: CampaignInfo, snaps: [DaySnapshot], trend: [TrendPoint], timeline: GoalTimeline,
                               required: Set<Tracker>, today: Date, calendar cal: Calendar = .current) -> CampaignReport {
        let t = cal.startOfDay(for: today)
        let end = min(c.end ?? t, t)
        let started = end >= c.start
        let span = started ? (cal.dateComponents([.day], from: c.start, to: end).day ?? 0) + 1 : 0
        let inRange = snaps.filter {
            let d = cal.startOfDay(for: $0.date); return d >= c.start && d <= end
        }
        let weighed = inRange.filter { $0.weightKg != nil }.count
        let tr = trend.filter { $0.date >= c.start && $0.date <= end }

        var avgWeekly: Double?
        if let a = tr.first, let b = tr.last, let gap = cal.dateComponents([.day], from: a.date, to: b.date).day, gap >= 7 {
            avgWeekly = (b.trendKg - a.trendKg) / Double(gap) * 7
        }
        let rates = rateOfChange(trend, calendar: cal).filter { $0.date >= c.start && $0.date <= end }
        let fastest = rates.max { abs($0.kgPerWeek) < abs($1.kgPerWeek) }?.kgPerWeek

        let comp = started
            ? Metrics.compliance(snaps, from: c.start, to: end, today: today, required: required, timeline: timeline, calendar: cal)
            : Compliance(windowDays: 0, compliedDays: 0, perTracker: [:], goalDays: 0)
        let strip = started
            ? Metrics.complianceStrip(snaps, from: c.start, to: end, today: today, required: required, timeline: timeline, calendar: cal)
            : []
        let g = goalResults(snaps, timeline: timeline, campaign: c, today: today, calendar: cal)

        var workoutDays = 0
        for s in inRange where s.ratings["performance"] != nil { workoutDays += 1 }

        var ratingAvg: [String: Double] = [:]
        for r in Rating.allCases {
            let v = inRange.compactMap { $0.ratings[r.rawValue].map(Double.init) }
            if !v.isEmpty { ratingAvg[r.rawValue] = v.reduce(0, +) / Double(v.count) }
        }

        return CampaignReport(
            days: span, daysLogged: inRange.filter { !$0.logged.isEmpty }.count, daysWeighed: weighed,
            startTrendKg: tr.first?.trendKg, endTrendKg: tr.last?.trendKg, avgWeeklyChangeKg: avgWeekly, fastestWeekKg: fastest,
            compliance: comp, strip: strip, dailyGoalDaysMet: g.dayMet, dailyGoalDays: g.dayTotal,
            weeklyGoalsMet: g.weekMet, weeklyGoals: g.weekTotal,
            workoutsPerWeek: span >= 7 ? Double(workoutDays) / (Double(span) / 7) : nil,
            goalsAtEnd: g.atEnd,
            averages: started ? averages(snaps, from: c.start, to: end, calendar: cal) : Averages(),
            ratingAverages: ratingAvg)
    }
}
