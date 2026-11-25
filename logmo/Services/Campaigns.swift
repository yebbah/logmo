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
}

/// What a store must do to start a campaign.
struct StartPlan: Equatable {
    var new: CampaignInfo
    var endDefault: (id: UUID, on: Date)?
    var deleteDefault: UUID?          // a default that would have lasted zero days
    var filler: (start: Date, end: Date)?   // maintenance between a running campaign's planned end and a queued one's start
    static func == (a: StartPlan, b: StartPlan) -> Bool {
        a.new == b.new && a.deleteDefault == b.deleteDefault
            && a.endDefault?.id == b.endDefault?.id && a.endDefault?.on == b.endDefault?.on
            && a.filler?.start == b.filler?.start && a.filler?.end == b.filler?.end
    }
}

enum CampaignRules {
    private static func addDays(_ n: Int, to d: Date, _ cal: Calendar) -> Date {
        cal.date(byAdding: .day, value: n, to: d)!
    }

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

    /// Cancelling an upcoming campaign: the default it was going to replace carries on. Returns that
    /// default's id (the one that ends the day before the start), nil if there isn't one.
    static func defaultToReopen(cancelling c: CampaignInfo, existing: [CampaignInfo], calendar cal: Calendar = .current) -> UUID? {
        let dayBefore = addDays(-1, to: c.start, cal)
        return existing.first { $0.isDefault && $0.end == dayBefore }?.id
    }

    /// Last planned day (inclusive), nil for open-ended campaigns.
    static func plannedEnd(_ c: CampaignInfo, calendar cal: Calendar = .current) -> Date? {
        c.plannedWeeks.map { addDays($0 * 7 - 1, to: c.start, cal) }
    }

    static func contains(_ c: CampaignInfo, day: Date, calendar cal: Calendar = .current) -> Bool {
        let d = cal.startOfDay(for: day)
        return d >= c.start && (c.end.map { d <= $0 } ?? true)
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

    /// The default maintenance campaign to create when nothing is open, else nil.
    /// It starts the day after the last campaign ended; with no history it starts on the
    /// first logged day, or today.
    static func defaultNeeded(existing: [CampaignInfo], earliestLog: Date?, today: Date,
                              calendar cal: Calendar = .current) -> CampaignInfo? {
        guard !existing.contains(where: isOpen) else { return nil }
        let start: Date
        if let lastEnd = existing.compactMap(\.end).max() {
            start = addDays(1, to: lastEnd, cal)
        } else {
            start = cal.startOfDay(for: earliestLog ?? today)
        }
        return CampaignInfo(number: nextNumber(existing), kind: .maintenance, isDefault: true, start: start)
    }

    /// Plan for starting a real campaign. A running real campaign must be ended first;
    /// a running default is closed the day before the new one starts.
    static func plan(start: Date, kind: CampaignKind, targetKg: Double?, weeks: Int,
                     existing: [CampaignInfo], label: String? = nil, today: Date = Date(),
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
            let gapStart = addDays(1, to: pe, cal)
            let filler: (start: Date, end: Date)? = s > gapStart ? (gapStart, addDays(-1, to: s, cal)) : nil
            let new = CampaignInfo(number: nextNumber(existing) + (filler == nil ? 0 : 1), kind: kind, isDefault: false,
                                   targetWeightKg: targetKg, start: s, plannedWeeks: weeks, label: cleanLabel(label))
            return .success(StartPlan(new: new, endDefault: nil, deleteDefault: nil, filler: filler))
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
                               start: s, plannedWeeks: weeks, label: cleanLabel(label))
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
