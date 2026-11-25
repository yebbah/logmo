import Foundation

enum CampaignKind: String, CaseIterable, Identifiable {
    case cut, bulk, maintenance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cut: "Cut"
        case .bulk: "Bulk"
        case .maintenance: "Maintenance"
        }
    }
}

/// Plain-value copy of a campaign, so the rules stay independent of SwiftData.
///
/// Every day belongs to exactly one campaign. When no real campaign is running, an
/// automatic *default* maintenance campaign is open, numbered after the previous one,
/// so the stretches between campaigns keep their own history.
struct CampaignInfo: Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var number: Int
    var kind: CampaignKind
    var isDefault: Bool = false        // automatic maintenance campaign
    var targetWeightKg: Double? = nil
    var start: Date                    // start of day
    var plannedWeeks: Int? = nil       // nil for a default campaign (open-ended)
    var end: Date? = nil               // last day, inclusive; nil = still open
    var endedEarly: Bool = false
    var label: String? = nil           // the user's own name for it, optional
    var startWeightKg: Double? = nil   // the weight the trend starts from when this campaign begins; asked for every real campaign

    /// The standard name, used when there is no label.
    var title: String { "Campaign \(number) · \(kind.title)\(isDefault ? " (default)" : "")" }

    /// What to call it: the label if there is one, else the standard name.
    var name: String {
        let l = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return l.isEmpty ? title : l
    }
}

enum CampaignError: Error, Equatable {
    case invalidWeeks
    case campaignRunning          // end the running campaign first
    case startsBeforeCurrent      // would overlap the previous campaign
    case notEditable              // only a campaign that hasn't started can have its dates changed
    case invalidStartWeight       // a real campaign needs a starting weight
}

/// What a store must do to start a campaign.
struct StartPlan: Equatable {
    var new: CampaignInfo
    var endDefault: (id: UUID, on: Date)?
    var deleteDefault: UUID?          // a default that would have lasted zero days
    static func == (a: StartPlan, b: StartPlan) -> Bool {
        a.new == b.new && a.deleteDefault == b.deleteDefault
            && a.endDefault?.id == b.endDefault?.id && a.endDefault?.on == b.endDefault?.on
    }
}

enum CampaignRules {
    private static func addDays(_ n: Int, to d: Date, _ cal: Calendar) -> Date {
        cal.date(byAdding: .day, value: n, to: d)!
    }

    /// Where the weight trend starts afresh: each real campaign that has a starting weight, on its first day. Campaigns without one
    /// (the automatic maintenance ones, and campaigns made before starting weights existed) carry the running trend on.
    static func trendSeeds(_ campaigns: [CampaignInfo], calendar cal: Calendar = .current) -> [Date: Double] {
        var out: [Date: Double] = [:]
        for c in campaigns where !c.isDefault { if let w = c.startWeightKg { out[cal.startOfDay(for: c.start)] = w } }
        return out
    }

    /// Where a new campaign's starting weight should begin: the trend weight as it stands (so the trend carries on from an earlier
    /// campaign), else the latest weigh-in; nil with no weigh-ins at all.
    static func suggestedStartWeight(snaps: [DaySnapshot], campaigns: [CampaignInfo], smoothingDays: Int, today: Date,
                                     calendar cal: Calendar = .current) -> Double? {
        let trend = Metrics.weightTrend(snaps, through: today, smoothingDays: smoothingDays, seeds: trendSeeds(campaigns, calendar: cal), calendar: cal)
        if let t = trend.last?.trendKg { return (t * 10).rounded() / 10 }
        return snaps.filter { $0.weightKg != nil }.max { $0.date < $1.date }?.weightKg
    }

    /// The Dashboard's week line: "Week 4 of 8" for the campaign running today (counted from its start), else "Week of 23 Nov"; and the
    /// Monday-to-Sunday dates of this week, which is what the weekly goals use.
    static func weekHeadline(_ campaigns: [CampaignInfo], today: Date, calendar cal: Calendar = .current) -> (title: String, dates: String) {
        let ws = Metrics.weekStart(of: today, calendar: cal)
        let we = cal.date(byAdding: .day, value: 6, to: ws)!
        let f = Date.FormatStyle().day().month(.abbreviated)
        let dates = "\(ws.formatted(f)) – \(we.formatted(f))"
        if let c = campaign(for: today, in: campaigns, calendar: cal), !c.isDefault, let total = c.plannedWeeks {
            return ("Week \(weekNumber(c, today: today, calendar: cal)) of \(total)", dates)
        }
        return ("This week", dates)
    }

    /// The Dashboard's top-left badge: days left in the running real campaign, counting today. nil when none is running with a planned end.
    static func daysLeftBadge(_ campaigns: [CampaignInfo], today: Date, calendar cal: Calendar = .current) -> String? {
        guard let c = campaign(for: today, in: campaigns, calendar: cal), !c.isDefault, c.end == nil, c.plannedWeeks != nil,
              !isUpcoming(c, today: today, calendar: cal), let left = daysLeft(c, today: today, calendar: cal) else { return nil }
        return left == 0 ? "Planned end passed" : "\(left) \(left == 1 ? "day" : "days") left"
    }

    /// A starting weight that could be a person's, in kg.
    static let plausibleStartWeightKg = 20.0...400.0
    static func isPlausibleStartWeight(_ kg: Double?) -> Bool { kg.map { plausibleStartWeightKg.contains($0) } ?? false }

    static func isOpen(_ c: CampaignInfo) -> Bool { c.end == nil }

    /// A campaign that has been planned but hasn't started yet.
    static func isUpcoming(_ c: CampaignInfo, today: Date, calendar cal: Calendar = .current) -> Bool {
        c.start > cal.startOfDay(for: today)
    }

    /// The dates a campaign covers, worked out from its settings so it follows any change:
    /// "29 Oct – 23 Dec" (to the planned last day while it runs, to the actual last day once ended,
    /// so ending early updates it), or "since 11 Nov" for an open-ended default. A year is added
    /// for dates outside the current year.
    static func periodText(_ c: CampaignInfo, today: Date = Date(), calendar cal: Calendar = .current) -> String {
        let thisYear = cal.component(.year, from: today)
        func f(_ d: Date) -> String {
            var style = Date.FormatStyle(timeZone: cal.timeZone).day().month(.abbreviated)
            if cal.component(.year, from: d) != thisYear { style = style.year() }
            return d.formatted(style)
        }
        guard let last = c.end ?? plannedEnd(c, calendar: cal) else { return "since \(f(c.start))" }
        return "\(f(c.start)) – \(f(last))"
    }

    /// Label (or standard name) with the period appended, for places that have room.
    static func titleWithPeriod(_ c: CampaignInfo, today: Date = Date(), calendar cal: Calendar = .current) -> String {
        "\(c.name) · \(periodText(c, today: today, calendar: cal))"
    }

    /// For menus: "#2 Summer cut · 29 Oct – 23 Dec" (number, then the label or the type, then the period).
    static func pickerName(_ c: CampaignInfo, today: Date = Date(), calendar cal: Calendar = .current) -> String {
        let l = cleanLabel(c.label) ?? "\(c.kind.title)\(c.isDefault ? " (default)" : "")"
        return "#\(c.number) \(l) · \(periodText(c, today: today, calendar: cal))"
    }

    /// Whole days until an upcoming campaign starts (0 once it has).
    static func daysUntilStart(_ c: CampaignInfo, today: Date, calendar cal: Calendar = .current) -> Int {
        max(0, cal.dateComponents([.day], from: cal.startOfDay(for: today), to: c.start).day ?? 0)
    }

    /// Last planned day (inclusive); nil only for an old automatic maintenance campaign.
    static func plannedEnd(_ c: CampaignInfo, calendar cal: Calendar = .current) -> Date? {
        c.plannedWeeks.map { addDays($0 * 7 - 1, to: c.start, cal) }
    }

    /// The last day a campaign covers: the day it ended, else its planned last day. Only an old automatic maintenance campaign that was
    /// never closed has neither, and covers every day from its start.
    static func lastDay(_ c: CampaignInfo, calendar cal: Calendar = .current) -> Date? {
        c.end ?? plannedEnd(c, calendar: cal)
    }

    /// A campaign covers its start to its last day and nothing after: days outside every campaign belong to none.
    static func contains(_ c: CampaignInfo, day: Date, calendar cal: Calendar = .current) -> Bool {
        let d = cal.startOfDay(for: day)
        return d >= c.start && (lastDay(c, calendar: cal).map { d <= $0 } ?? true)
    }

    /// The campaign a day belongs to (latest start wins if ever ambiguous).
    static func campaign(for day: Date, in all: [CampaignInfo], calendar cal: Calendar = .current) -> CampaignInfo? {
        all.filter { contains($0, day: day, calendar: cal) }.max { $0.start < $1.start }
    }

    /// Countdown to the last planned day, counting today: a 4-week campaign shows 28 on its
    /// first day, 1 on its last planned day, and 0 once that day has passed.
    static func daysLeft(_ c: CampaignInfo, today: Date, calendar cal: Calendar = .current) -> Int? {
        guard let planned = plannedEnd(c, calendar: cal) else { return nil }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: today), to: planned).day ?? 0
        return max(0, days + 1)
    }

    /// 1-based week of the campaign that `today` falls in (clamped to the planned length).
    static func weekNumber(_ c: CampaignInfo, today: Date, calendar cal: Calendar = .current) -> Int {
        let d = cal.dateComponents([.day], from: c.start, to: cal.startOfDay(for: today)).day ?? 0
        let w = max(0, d) / 7 + 1
        return c.plannedWeeks.map { min(w, $0) } ?? w
    }

    static func nextNumber(_ all: [CampaignInfo]) -> Int { (all.map(\.number).max() ?? 0) + 1 }

    /// Plan for starting a campaign. It always has a start and a length, so a start and an end. Days between two campaigns belong to none.
    /// (A running automatic maintenance campaign from an older version, if one is still open, is closed the day before.)
    static func plan(start: Date, kind: CampaignKind, targetKg: Double?, weeks: Int,
                     existing: [CampaignInfo], label: String? = nil, startWeightKg: Double? = nil, today: Date = Date(),
                     calendar cal: Calendar = .current) -> Result<StartPlan, CampaignError> {
        guard weeks >= 1 else { return .failure(.invalidWeeks) }
        let s = cal.startOfDay(for: start)
        let open = existing.filter(isOpen)
        if let r = open.first(where: { !$0.isDefault }) {
            // A campaign is running: the next one can be queued to start after its planned end.
            // A campaign that is itself only planned blocks this: one upcoming campaign at a time.
            guard !isUpcoming(r, today: today, calendar: cal), let pe = plannedEnd(r, calendar: cal) else {
                return .failure(.campaignRunning)
            }
            if s <= pe { return .failure(.startsBeforeCurrent) }
            let new = CampaignInfo(number: nextNumber(existing), kind: kind, isDefault: false,
                                   targetWeightKg: targetKg, start: s, plannedWeeks: weeks, label: cleanLabel(label), startWeightKg: startWeightKg)
            return .success(StartPlan(new: new, endDefault: nil, deleteDefault: nil))
        }

        var endDefault: (id: UUID, on: Date)?
        var deleteDefault: UUID?
        if let d = open.first(where: \.isDefault) {
            if s < d.start { return .failure(.startsBeforeCurrent) }
            if s == d.start { deleteDefault = d.id } else { endDefault = (d.id, addDays(-1, to: s, cal)) }
        } else if let lastEnd = existing.compactMap(\.end).max(), s <= lastEnd {
            return .failure(.startsBeforeCurrent)
        }
        let number = nextNumber(existing.filter { $0.id != deleteDefault })
        let new = CampaignInfo(number: number, kind: kind, isDefault: false, targetWeightKg: targetKg,
                               start: s, plannedWeeks: weeks, label: cleanLabel(label), startWeightKg: startWeightKg)
        return .success(StartPlan(new: new, endDefault: endDefault, deleteDefault: deleteDefault))
    }

    /// The earliest day a not-yet-started campaign (other than `excluding`) may begin: tomorrow at the soonest, and
    /// after the planned end of a campaign that is running.
    static func earliestUpcomingStart(existing: [CampaignInfo], excluding: UUID? = nil, today: Date,
                                      calendar cal: Calendar = .current) -> Date {
        var earliest = addDays(1, to: cal.startOfDay(for: today), cal)
        if let r = existing.first(where: { $0.id != excluding && !$0.isDefault && $0.end == nil && !isUpcoming($0, today: today, calendar: cal) }),
           let pe = plannedEnd(r, calendar: cal) {
            earliest = max(earliest, addDays(1, to: pe, cal))
        }
        return earliest
    }

    /// Days left (1 to 7) of a running real campaign that is about to close, nil otherwise.
    static func closingIn(_ c: CampaignInfo, today: Date, calendar cal: Calendar = .current) -> Int? {
        guard !c.isDefault, c.end == nil, !isUpcoming(c, today: today, calendar: cal),
              let left = daysLeft(c, today: today, calendar: cal), (1...7).contains(left) else { return nil }
        return left
    }

    /// A label trimmed and capped at 40 characters; nil when empty.
    static func cleanLabel(_ raw: String?) -> String? {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(40))
    }

    /// Ending a campaign on `day`. It is "early" when that is before the planned last day.
    static func ending(_ c: CampaignInfo, on day: Date, calendar cal: Calendar = .current) -> (end: Date, early: Bool) {
        let d = max(cal.startOfDay(for: day), c.start)
        let early = plannedEnd(c, calendar: cal).map { d < $0 } ?? false
        return (d, early)
    }
}
