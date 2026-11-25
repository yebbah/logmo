import Foundation

/// Weekly goals grouped by campaign. A day uses the goals of the campaign it belongs to,
/// and within a campaign the latest goals set for that week or earlier. A week's calorie
/// goal belongs to the campaign that contains the week's Monday.
struct GoalBook: Equatable {
    var campaigns: [CampaignInfo]
    var byCampaign: [UUID: [Date: GoalSet]]      // campaign id → (Monday → goals)

    var isEmpty: Bool { byCampaign.values.allSatisfy { $0.isEmpty } }
    var firstWeek: Date? { byCampaign.values.flatMap { $0.keys }.min() }

    private func latest(_ id: UUID, upTo ws: Date) -> GoalSet? {
        guard let m = byCampaign[id], let k = m.keys.filter({ $0 <= ws }).max() else { return nil }
        return m[k]
    }

    func goals(forDay d: Date, calendar cal: Calendar = .current) -> GoalSet? {
        guard let c = CampaignRules.campaign(for: d, in: campaigns, calendar: cal) else { return nil }
        return latest(c.id, upTo: Metrics.weekStart(of: d, calendar: cal))
    }

    /// The campaign a week's goals belong to: the one containing its Monday, else the first
    /// campaign that overlaps the week.
    func owner(ofWeek ws: Date, calendar cal: Calendar = .current) -> CampaignInfo? {
        if let c = CampaignRules.campaign(for: ws, in: campaigns, calendar: cal) { return c }
        let end = cal.date(byAdding: .day, value: 6, to: ws)!
        return campaigns.filter { $0.start <= end && ($0.end.map { $0 >= ws } ?? true) }.min { $0.start < $1.start }
    }

    func goals(forWeekStarting ws: Date, calendar cal: Calendar = .current) -> GoalSet? {
        guard let c = owner(ofWeek: ws, calendar: cal) else { return nil }
        return latest(c.id, upTo: ws)
    }
}

/// One weekly goal set, with the campaign it belongs to. Plain values for the rules below.
struct StoredGoal: Equatable {
    var campaignID: UUID?
    var weekStart: Date
    var goals: GoalSet
}

enum GoalRules {
    /// Builds the book. A goal with no campaign (made before goals were per campaign) goes to
    /// the campaign containing its Monday, or the earliest campaign if none does.
    static func book(campaigns: [CampaignInfo], goals: [StoredGoal], calendar cal: Calendar = .current) -> GoalBook {
        var by: [UUID: [Date: GoalSet]] = [:]
        for g in goals {
            let id = g.campaignID ?? assignedCampaign(for: g.weekStart, in: campaigns, calendar: cal)?.id
            guard let id else { continue }
            by[id, default: [:]][g.weekStart] = g.goals
        }
        return GoalBook(campaigns: campaigns, byCampaign: by)
    }

    static func assignedCampaign(for weekStart: Date, in campaigns: [CampaignInfo], calendar cal: Calendar = .current) -> CampaignInfo? {
        CampaignRules.campaign(for: weekStart, in: campaigns, calendar: cal) ?? campaigns.min { $0.start < $1.start }
    }

    /// The goals a new campaign starts with: a copy of the most recent weekly goals of any
    /// other campaign, placed on the Monday of the week the new campaign starts.
    static func seed(for newCampaign: CampaignInfo, from existing: [StoredGoal], calendar cal: Calendar = .current)
        -> (weekStart: Date, goals: GoalSet)?
    {
        let candidates = existing.filter { $0.campaignID != newCampaign.id }
        guard let latest = candidates.max(by: { $0.weekStart < $1.weekStart }) else { return nil }
        return (Metrics.weekStart(of: newCampaign.start, calendar: cal), latest.goals)
    }
}
