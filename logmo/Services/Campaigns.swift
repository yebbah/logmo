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
struct CampaignInfo: Identifiable, Equatable {
    var id: UUID = UUID()
    var number: Int
    var kind: CampaignKind
    var isDefault: Bool = false        // automatic maintenance campaign
    var targetWeightKg: Double? = nil
    var start: Date                    // start of day
    var plannedWeeks: Int? = nil       // nil for a default campaign (open-ended)
    var end: Date? = nil               // last day, inclusive; nil = still open
    var endedEarly: Bool = false

    var title: String { "Campaign \(number) · \(kind.title)\(isDefault ? " (default)" : "")" }
}

enum CampaignError: Error, Equatable {
    case invalidWeeks
    case campaignRunning          // end the running campaign first
    case startsBeforeCurrent      // would overlap the previous campaign
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

    static func isOpen(_ c: CampaignInfo) -> Bool { c.end == nil }

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

    /// Whole days left after today until the planned end; 0 once it is reached or passed.
    static func daysLeft(_ c: CampaignInfo, today: Date, calendar cal: Calendar = .current) -> Int? {
        guard let planned = plannedEnd(c, calendar: cal) else { return nil }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: today), to: planned).day ?? 0
        return max(0, days)
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
                     existing: [CampaignInfo], calendar cal: Calendar = .current) -> Result<StartPlan, CampaignError> {
        guard weeks >= 1 else { return .failure(.invalidWeeks) }
        let s = cal.startOfDay(for: start)
        let open = existing.filter(isOpen)
        if open.contains(where: { !$0.isDefault }) { return .failure(.campaignRunning) }

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
                               start: s, plannedWeeks: weeks)
        return .success(StartPlan(new: new, endDefault: endDefault, deleteDefault: deleteDefault))
    }

    /// Ending a campaign on `day`. It is "early" when that is before the planned last day.
    static func ending(_ c: CampaignInfo, on day: Date, calendar cal: Calendar = .current) -> (end: Date, early: Bool) {
        let d = max(cal.startOfDay(for: day), c.start)
        let early = plannedEnd(c, calendar: cal).map { d < $0 } ?? false
        return (d, early)
    }
}
