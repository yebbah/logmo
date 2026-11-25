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
                      weeks: Int, label: String? = nil, today: Date = Date()) -> Result<Void, CampaignError> {
        let campaigns = all(context)
        switch CampaignRules.plan(start: start, kind: kind, targetKg: targetKg, weeks: weeks,
                                  existing: campaigns.map(\.info), label: label, today: today) {
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
            if let f = plan.filler {
                let info = CampaignInfo(number: plan.new.number - 1, kind: .maintenance, isDefault: true, start: f.start, end: f.end)
                context.insert(Campaign(info))
                seedGoals(context, for: info, from: source)
            }
            context.insert(Campaign(plan.new))
            seedGoals(context, for: plan.new, from: source)
            try? context.save()
            return .success(())
        }
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

    /// The maintenance campaign that fills the days just before `u`.
    private static func fillerBefore(_ u: Campaign, in campaigns: [Campaign]) -> Campaign? {
        let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: u.start)!
        return campaigns.first { $0.isDefault && $0.end == dayBefore }
    }

    /// Lay out the days between the end of `running` (or the closing maintenance) and the start of `u`.
    private static func relayGap(_ context: ModelContext, running: Campaign?, upcoming u: Campaign, oldStart: Date,
                                 newStart: Date, today: Date) {
        let cal = Calendar.current
        let campaigns = all(context)
        let oldDayBefore = cal.date(byAdding: .day, value: -1, to: oldStart)!
        let filler = campaigns.first { $0.isDefault && $0.end == oldDayBefore && $0.id != u.id }
        let newDayBefore = cal.date(byAdding: .day, value: -1, to: newStart)!
        if let r = running, let pe = CampaignRules.plannedEnd(r.info) {
            let gapStart = cal.date(byAdding: .day, value: 1, to: r.end ?? pe)!
            if newStart > gapStart {
                if let f = filler { f.start = gapStart; f.end = newDayBefore; f.updatedAt = Date() }
                else {
                    let info = CampaignInfo(number: u.number, kind: .maintenance, isDefault: true, start: gapStart, end: newDayBefore)
                    context.insert(Campaign(info)); seedGoals(context, for: info)
                    u.number += 1
                }
            } else if let f = filler {
                u.number = min(u.number, f.number)
                for g in allGoals(context) where g.campaignID == f.id { context.delete(g) }
                context.delete(f)
            }
        } else if let d = filler {
            d.end = newDayBefore; d.updatedAt = Date()             // the maintenance before it carries on until the new start
        }
    }

    /// Change when an upcoming campaign starts and how long it runs. Only a campaign that hasn't started can change.
    @discardableResult
    static func reschedule(_ context: ModelContext, _ campaign: Campaign, start: Date, weeks: Int,
                           today: Date = Date()) -> Result<Void, CampaignError> {
        let cal = Calendar.current
        guard !campaign.isDefault, campaign.end == nil, CampaignRules.isUpcoming(campaign.info, today: today) else { return .failure(.notEditable) }
        guard weeks >= 1 else { return .failure(.invalidWeeks) }
        let s = cal.startOfDay(for: start)
        let earliest = CampaignRules.earliestUpcomingStart(existing: all(context).map(\.info), excluding: campaign.id, today: today)
        guard s >= earliest else { return .failure(.startsBeforeCurrent) }

        let old = campaign.start
        let source = allGoals(context).filter { $0.campaignID != campaign.id }.map(\.stored)
        relayGap(context, running: running(context, today: today), upcoming: campaign, oldStart: old, newStart: s, today: today)
        for g in allGoals(context) where g.campaignID == campaign.id { context.delete(g) }
        campaign.start = s
        campaign.plannedWeeks = weeks
        campaign.updatedAt = Date()
        seedGoals(context, for: campaign.info, from: source)         // its goals are copied again for the new weeks
        try? context.save()
        return .success(())
    }

    /// Cancel a campaign that hasn't started: it and its goals are removed. If it was queued behind a running
    /// campaign, that one carries on; otherwise the default maintenance campaign it would have replaced does.
    static func cancelUpcoming(_ context: ModelContext, _ campaign: Campaign, today: Date = Date()) {
        guard !campaign.isDefault, campaign.end == nil,
              CampaignRules.isUpcoming(campaign.info, today: today) else { return }
        let runningNow = running(context, today: today)
        let id = CampaignRules.defaultToReopen(cancelling: campaign.info, existing: all(context).map(\.info))
        for g in allGoals(context) where g.campaignID == campaign.id { context.delete(g) }
        if runningNow != nil {
            if let id, let f = all(context).first(where: { $0.id == id }) {
                for g in allGoals(context) where g.campaignID == f.id { context.delete(g) }
                context.delete(f)
            }
        } else if let id, let d = all(context).first(where: { $0.id == id }) { d.end = nil; d.updatedAt = Date() }
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
        // A campaign queued after this one: maintenance fills the days from tomorrow to its start.
        if let u = upcoming(context, today: today) {
            let cal = Calendar.current
            let gapStart = cal.date(byAdding: .day, value: 1, to: r.end)!
            if gapStart < u.start {
                let dayBefore = cal.date(byAdding: .day, value: -1, to: u.start)!
                if let f = fillerBefore(u, in: all(context)) { f.start = gapStart; f.updatedAt = Date() }
                else {
                    let info = CampaignInfo(number: u.number, kind: .maintenance, isDefault: true, start: gapStart, end: dayBefore)
                    context.insert(Campaign(info)); seedGoals(context, for: info)
                    u.number += 1
                }
            }
        }
        try? context.save()
        ensureDefault(context, today: today)
    }

    /// Close a campaign whose planned days are over, on its last planned day (not an early end).
    static func finish(_ context: ModelContext, _ campaign: Campaign, today: Date = Date()) {
        guard !campaign.isDefault, campaign.end == nil, let last = CampaignRules.plannedEnd(campaign.info) else { return }
        campaign.end = last
        campaign.endedEarly = false
        campaign.updatedAt = Date()
        try? context.save()
        ensureDefault(context, today: today)
    }

    /// Lengthen a running campaign by whole weeks. Refused when it would run into a campaign queued after it;
    /// that one's start date has to move first. Days of maintenance between them just shrink.
    @discardableResult
    static func extend(_ context: ModelContext, _ campaign: Campaign, byWeeks weeks: Int) -> Bool {
        guard !campaign.isDefault, campaign.end == nil, let planned = campaign.plannedWeeks, weeks > 0 else { return false }
        var info = campaign.info; info.plannedWeeks = planned + weeks
        guard let newEnd = CampaignRules.plannedEnd(info) else { return false }
        let cal = Calendar.current
        let campaigns = all(context)
        let later = campaigns.filter { $0.id != campaign.id && !$0.isDefault && $0.start > campaign.start }
        if later.contains(where: { $0.start <= newEnd }) { return false }
        if let u = later.min(by: { $0.start < $1.start }), let f = fillerBefore(u, in: campaigns), f.start > campaign.start {
            let newGapStart = cal.date(byAdding: .day, value: 1, to: newEnd)!
            if let fEnd = f.end, newGapStart > fEnd {
                u.number = min(u.number, f.number)
                for g in allGoals(context) where g.campaignID == f.id { context.delete(g) }
                context.delete(f)
            } else { f.start = newGapStart; f.updatedAt = Date() }
        }
        campaign.plannedWeeks = planned + weeks
        campaign.updatedAt = Date()
        try? context.save()
        return true
    }
}
