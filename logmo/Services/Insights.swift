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
            guard let goal = timeline.goals(forWeekStarting: Metrics.weekStart(of: d, calendar: cal))?.proteinDaily
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
