import Foundation
import SwiftData

/// SwiftData side of campaigns. The rules themselves live in CampaignRules.
@MainActor
enum CampaignStore {
    static func all(_ context: ModelContext) -> [Campaign] {
        (try? context.fetch(FetchDescriptor<Campaign>(sortBy: [SortDescriptor(\.number)]))) ?? []
    }

    /// Housekeeping, run whenever a campaign screen appears. Nothing is ever created here: a campaign exists only because the user made one,
    /// with a start and an end. An automatic maintenance campaign left open by an older version is closed the day before today (or removed
    /// if it hadn't begun), so no campaign is open-ended any more; its days stay in history.
    static func tidy(_ context: ModelContext, today: Date = Date()) {
        let cal = Calendar.current
        let day = cal.startOfDay(for: today)
        for d in all(context) where d.isDefault && d.end == nil {
            if d.start >= day {
                for g in allGoals(context) where g.campaignID == d.id { context.delete(g) }
                context.delete(d)
            } else {
                d.end = cal.date(byAdding: .day, value: -1, to: day)!
                d.updatedAt = Date()
            }
        }
        assignOrphanGoals(context)
        settle(context, today: today)
        try? context.save()
    }

    /// A running campaign whose planned days are over, with another campaign queued after it, is closed on its
    /// planned last day (not as ended early), so the two never claim the same days.
    static func settle(_ context: ModelContext, today: Date = Date()) {
        let campaigns = all(context)
        let day = Calendar.current.startOfDay(for: today)
        for r in campaigns where !r.isDefault && r.end == nil {
            if let pe = CampaignRules.plannedEnd(r.info), pe < day,
               campaigns.contains(where: { $0.id != r.id && $0.start > r.start }) {
                r.end = pe; r.endedEarly = false; r.updatedAt = Date()
            }
        }
    }

    private static func allGoals(_ context: ModelContext) -> [WeekGoal] {
        (try? context.fetch(FetchDescriptor<WeekGoal>())) ?? []
    }

    /// A new campaign starts with a copy of the most recent weekly goals, so nothing is unset.
    static func seedGoals(_ context: ModelContext, for info: CampaignInfo, from source: [StoredGoal]? = nil) {
        let existing = source ?? allGoals(context).map(\.stored)
        guard let seed = GoalRules.seed(for: info, from: existing) else { return }
        let g = WeekGoal(weekStart: seed.weekStart, campaignID: info.id)
        g.confirmed = false                                     // a copy: the user hasn't set it yet
        g.caloriesWeekly = seed.goals.caloriesWeekly
        g.caloriesAtOrUnder = seed.goals.caloriesAtOrUnder
        g.proteinDaily = seed.goals.proteinDaily
        g.stepsDaily = seed.goals.stepsDaily
        g.stepsIsWeeklyAverage = seed.goals.stepsIsWeeklyAverage
        g.waterDailyMl = seed.goals.waterDailyMl
        g.workoutDaysWeekly = seed.goals.workoutDaysWeekly
        g.carbsDaily = seed.goals.carbsDaily
        g.fatDaily = seed.goals.fatDaily
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
                      weeks: Int, label: String? = nil, startWeightKg: Double?, measureEveryDays: Int = 0,
                      today: Date = Date()) -> Result<Void, CampaignError> {
        // Every real campaign starts with a weight, so the trend always has a known starting point.
        guard CampaignRules.isPlausibleStartWeight(startWeightKg) else { return .failure(.invalidStartWeight) }
        let campaigns = all(context)
        switch CampaignRules.plan(start: start, kind: kind, targetKg: targetKg, weeks: weeks,
                                  existing: campaigns.map(\.info), label: label, startWeightKg: startWeightKg, today: today) {
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
            var new = plan.new
            new.measureEveryDays = measureEveryDays
            context.insert(Campaign(new))
            seedGoals(context, for: new, from: source)
            try? context.save()
            return .success(())
        }
    }

    /// Set or change the starting weight of a campaign that hasn't ended. Past campaigns keep theirs.
    @discardableResult
    static func setStartWeight(_ context: ModelContext, _ campaign: Campaign, kg: Double) -> Result<Void, CampaignError> {
        guard !campaign.isDefault, campaign.end == nil else { return .failure(.notEditable) }
        guard CampaignRules.isPlausibleStartWeight(kg) else { return .failure(.invalidStartWeight) }
        campaign.startWeightKg = kg
        campaign.updatedAt = Date()
        try? context.save()
        return .success(())
    }

    /// Rename a campaign that hasn't ended. Past campaigns are read-only.
    static func rename(_ context: ModelContext, _ campaign: Campaign, to label: String) {
        guard campaign.end == nil else { return }
        campaign.label = CampaignRules.cleanLabel(label)
        campaign.updatedAt = Date()
        try? context.save()
    }

    // MARK: Queued campaigns (running now, another planned after it)

    /// The running real campaign, if any.
    static func running(_ context: ModelContext, today: Date = Date()) -> Campaign? {
        all(context).first { !$0.isDefault && $0.end == nil && !CampaignRules.isUpcoming($0.info, today: today) }
    }

    /// The real campaign that hasn't started yet, if any.
    static func upcoming(_ context: ModelContext, today: Date = Date()) -> Campaign? {
        all(context).first { !$0.isDefault && $0.end == nil && CampaignRules.isUpcoming($0.info, today: today) }
    }

    /// Change when an upcoming campaign starts and how long it runs. Only a campaign that hasn't started can change.
    @discardableResult
    static func reschedule(_ context: ModelContext, _ campaign: Campaign, start: Date, weeks: Int, startWeightKg: Double? = nil,
                           measureEveryDays: Int? = nil, today: Date = Date()) -> Result<Void, CampaignError> {
        let cal = Calendar.current
        guard !campaign.isDefault, campaign.end == nil, CampaignRules.isUpcoming(campaign.info, today: today) else { return .failure(.notEditable) }
        guard weeks >= 1 else { return .failure(.invalidWeeks) }
        if let w = startWeightKg, !CampaignRules.isPlausibleStartWeight(w) { return .failure(.invalidStartWeight) }
        let s = cal.startOfDay(for: start)
        let earliest = CampaignRules.earliestUpcomingStart(existing: all(context).map(\.info), excluding: campaign.id, today: today)
        guard s >= earliest else { return .failure(.startsBeforeCurrent) }

        let source = allGoals(context).filter { $0.campaignID != campaign.id }.map(\.stored)
        for g in allGoals(context) where g.campaignID == campaign.id { context.delete(g) }
        campaign.start = s
        campaign.plannedWeeks = weeks
        if let w = startWeightKg { campaign.startWeightKg = w }
        if let m = measureEveryDays { campaign.measureEveryDays = m }
        campaign.updatedAt = Date()
        seedGoals(context, for: campaign.info, from: source)         // its goals are copied again for the new weeks
        try? context.save()
        return .success(())
    }

    /// Cancel a campaign that hasn't started: it and its goals are removed. Nothing else changes.
    static func cancelUpcoming(_ context: ModelContext, _ campaign: Campaign, today: Date = Date()) {
        guard !campaign.isDefault, campaign.end == nil,
              CampaignRules.isUpcoming(campaign.info, today: today) else { return }
        for g in allGoals(context) where g.campaignID == campaign.id { context.delete(g) }
        context.delete(campaign)
        try? context.save()
    }

    /// End a campaign today (early if before its planned last day). The days after it belong to no campaign until the next one is started.
    static func end(_ context: ModelContext, _ campaign: Campaign, today: Date = Date()) {
        guard !campaign.isDefault, campaign.end == nil else { return }
        if CampaignRules.isUpcoming(campaign.info, today: today) { cancelUpcoming(context, campaign, today: today); return }
        let r = CampaignRules.ending(campaign.info, on: today)
        campaign.end = r.end
        campaign.endedEarly = r.early
        campaign.updatedAt = Date()
        try? context.save()
        tidy(context, today: today)
    }

    /// Close a campaign whose planned days are over, on its last planned day (not an early end).
    static func finish(_ context: ModelContext, _ campaign: Campaign, today: Date = Date()) {
        guard !campaign.isDefault, campaign.end == nil, let last = CampaignRules.plannedEnd(campaign.info) else { return }
        campaign.end = last
        campaign.endedEarly = false
        campaign.updatedAt = Date()
        try? context.save()
        tidy(context, today: today)
    }

    /// Lengthen a running campaign by whole weeks. Refused when it would run into a campaign queued after it;
    /// that one's start date has to move first.
    @discardableResult
    static func extend(_ context: ModelContext, _ campaign: Campaign, byWeeks weeks: Int) -> Bool {
        guard !campaign.isDefault, campaign.end == nil, let planned = campaign.plannedWeeks, weeks > 0 else { return false }
        var info = campaign.info; info.plannedWeeks = planned + weeks
        guard let newEnd = CampaignRules.plannedEnd(info) else { return false }
        let campaigns = all(context)
        let later = campaigns.filter { $0.id != campaign.id && !$0.isDefault && $0.start > campaign.start }
        if later.contains(where: { $0.start <= newEnd }) { return false }
        campaign.plannedWeeks = planned + weeks
        campaign.updatedAt = Date()
        try? context.save()
        return true
    }
}
