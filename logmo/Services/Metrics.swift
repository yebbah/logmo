import Foundation

/// The things a user can log in a day.
enum Tracker: String, CaseIterable, Identifiable {
    case weight, food, water, checkIn
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weight: "Weight"
        case .food: "Food"
        case .water: "Water"
        case .checkIn: "Check-in"
        }
    }
}

/// Plain-value view of one day's log. Keeps the maths independent of SwiftData.
struct DaySnapshot: Equatable {
    var date: Date                // any time on the day; normalised by callers
    var weightKg: Double?
    var logged: Set<Tracker>
}

struct TrendPoint: Identifiable, Equatable {
    var date: Date
    var weightKg: Double?   // measured, nil when no weigh-in that day
    var trendKg: Double     // smoothed
    var id: Date { date }
}

struct Compliance: Equatable {
    var windowDays: Int
    var daysLogged: Int                 // days with at least one tracker logged
    var perTracker: [Tracker: Int]      // days each tracker was logged
    var rate: Double { windowDays == 0 ? 0 : Double(daysLogged) / Double(windowDays) }
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

    /// Current and longest run of consecutive days with at least one tracker logged.
    /// Today not being logged *yet* does not break the current streak.
    static func streak(_ days: [DaySnapshot], today: Date, calendar cal: Calendar = .current)
        -> (current: Int, longest: Int)
    {
        let map = byDay(days, cal).filter { !$0.value.logged.isEmpty }
        let t = cal.startOfDay(for: today)

        var current = 0
        var cursor = map[t] != nil ? t : cal.date(byAdding: .day, value: -1, to: t)!
        while map[cursor] != nil {
            current += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }

        var longest = 0, run = 0
        var prev: Date?
        for d in map.keys.sorted() {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            longest = max(longest, run)
            prev = d
        }
        return (current, longest)
    }

    /// Compliance over the last `windowDays` days, ending today inclusive.
    static func compliance(_ days: [DaySnapshot], today: Date, windowDays: Int,
                           calendar cal: Calendar = .current) -> Compliance {
        let map = byDay(days, cal)
        let t = cal.startOfDay(for: today)
        var logged = 0
        var per: [Tracker: Int] = [:]
        for offset in 0..<windowDays {
            let d = cal.date(byAdding: .day, value: -offset, to: t)!
            guard let s = map[d], !s.logged.isEmpty else { continue }
            logged += 1
            for tr in s.logged { per[tr, default: 0] += 1 }
        }
        return Compliance(windowDays: windowDays, daysLogged: logged, perTracker: per)
    }

    /// Exponentially smoothed weight. Missing days carry the previous trend forward
    /// (never treated as zero). Series runs from the first weigh-in to `through`.
    static func weightTrend(_ days: [DaySnapshot], through: Date, smoothingDays: Int = 16,
                            calendar cal: Calendar = .current) -> [TrendPoint] {
        let map = byDay(days, cal)
        let weighed = map.values.filter { $0.weightKg != nil }.map { cal.startOfDay(for: $0.date) }.sorted()
        guard let first = weighed.first else { return [] }
        let a = alpha(forDays: smoothingDays)
        let end = max(cal.startOfDay(for: through), first)

        var out: [TrendPoint] = []
        var trend: Double?
        var cursor = first
        while cursor <= end {
            let w = map[cursor]?.weightKg
            if let w { trend = trend.map { a * w + (1 - a) * $0 } ?? w }
            if let trend { out.append(TrendPoint(date: cursor, weightKg: w, trendKg: trend)) }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return out
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
