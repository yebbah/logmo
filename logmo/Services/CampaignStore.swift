import Foundation
import SwiftData

/// SwiftData side of campaigns. The rules themselves live in CampaignRules.
@MainActor
enum CampaignStore {
    static func all(_ context: ModelContext) -> [Campaign] {
        (try? context.fetch(FetchDescriptor<Campaign>(sortBy: [SortDescriptor(\.number)]))) ?? []
    }

    /// Keep the invariant that a campaign is always open: if none is, add the default
    /// maintenance campaign. A default that starts later than the first logged day is
    /// stretched back so no logged day sits outside every campaign.
    static func ensureDefault(_ context: ModelContext, today: Date = Date()) {
        let cal = Calendar.current
        let campaigns = all(context)
        let firstLog = (try? context.fetch(FetchDescriptor<DayLog>(sortBy: [SortDescriptor(\.day)])))?.first?.day

        if let firstLog, let first = campaigns.min(by: { $0.start < $1.start }), first.isDefault,
           cal.startOfDay(for: firstLog) < first.start {
            first.start = cal.startOfDay(for: firstLog)
            first.updatedAt = Date()
        }
        if let d = CampaignRules.defaultNeeded(existing: campaigns.map(\.info), earliestLog: firstLog, today: today) {
            context.insert(Campaign(d))
            seedGoals(context, for: d)
        }
        assignOrphanGoals(context)
        try? context.save()
    }

    private static func allGoals(_ context: ModelContext) -> [WeekGoal] {
        (try? context.fetch(FetchDescriptor<WeekGoal>())) ?? []
    }

    /// A new campaign starts with a copy of the most recent weekly goals, so nothing is unset.
    static func seedGoals(_ context: ModelContext, for info: CampaignInfo, from source: [StoredGoal]? = nil) {
        let existing = source ?? allGoals(context).map(\.stored)
        guard let seed = GoalRules.seed(for: info, from: existing) else { return }
        let g = WeekGoal(weekStart: seed.weekStart, campaignID: info.id)
        g.caloriesWeekly = seed.goals.caloriesWeekly
        g.caloriesAtOrUnder = seed.goals.caloriesAtOrUnder
        g.proteinDaily = seed.goals.proteinDaily
        g.stepsDaily = seed.goals.stepsDaily
        g.stepsIsWeeklyAverage = seed.goals.stepsIsWeeklyAverage
        g.waterDailyMl = seed.goals.waterDailyMl
        g.workoutDaysWeekly = seed.goals.workoutDaysWeekly
        context.insert(g)
    }

    /// Goals made before goals belonged to campaigns are attached to the campaign containing their week.
    static func assignOrphanGoals(_ context: ModelContext) {
        let infos = all(context).map(\.info)
        for g in allGoals(context) where g.campaignID == nil {
            g.campaignID = GoalRules.assignedCampaign(for: g.weekStart, in: infos)?.id
        }
    }

    @discardableResult
    static func start(_ context: ModelContext, kind: CampaignKind, targetKg: Double?, start: Date,
                      weeks: Int) -> Result<Void, CampaignError> {
        let campaigns = all(context)
        switch CampaignRules.plan(start: start, kind: kind, targetKg: targetKg, weeks: weeks,
                                  existing: campaigns.map(\.info)) {
        case .failure(let e):
            return .failure(e)
        case .success(let plan):
            let source = allGoals(context).map(\.stored)            // taken before anything is deleted
            if let del = plan.deleteDefault {
                if let m = campaigns.first(where: { $0.id == del }) { context.delete(m) }
                for g in allGoals(context) where g.campaignID == del { context.delete(g) }
            }
            if let e = plan.endDefault, let m = campaigns.first(where: { $0.id == e.id }) {
                m.end = e.on; m.updatedAt = Date()
            }
            context.insert(Campaign(plan.new))
            seedGoals(context, for: plan.new, from: source)
            try? context.save()
            return .success(())
        }
    }

    /// Cancel a campaign that hasn't started: it and its goals are removed, and the default
    /// campaign it would have replaced carries on.
    static func cancelUpcoming(_ context: ModelContext, _ campaign: Campaign, today: Date = Date()) {
        guard !campaign.isDefault, campaign.end == nil,
              CampaignRules.isUpcoming(campaign.info, today: today) else { return }
        let id = CampaignRules.defaultToReopen(cancelling: campaign.info, existing: all(context).map(\.info))
        for g in allGoals(context) where g.campaignID == campaign.id { context.delete(g) }
        if let id, let d = all(context).first(where: { $0.id == id }) { d.end = nil; d.updatedAt = Date() }
        context.delete(campaign)
        try? context.save()
    }

    /// End a real campaign today (early if before its planned last day). A default
    /// maintenance campaign then opens the next day.
    static func end(_ context: ModelContext, _ campaign: Campaign, today: Date = Date()) {
        guard !campaign.isDefault, campaign.end == nil else { return }
        if CampaignRules.isUpcoming(campaign.info, today: today) { cancelUpcoming(context, campaign, today: today); return }
        let r = CampaignRules.ending(campaign.info, on: today)
        campaign.end = r.end
        campaign.endedEarly = r.early
        campaign.updatedAt = Date()
        try? context.save()
        ensureDefault(context, today: today)
    }
}
