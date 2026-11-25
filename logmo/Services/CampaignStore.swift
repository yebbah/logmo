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
        }
        try? context.save()
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
            if let del = plan.deleteDefault, let m = campaigns.first(where: { $0.id == del }) { context.delete(m) }
            if let e = plan.endDefault, let m = campaigns.first(where: { $0.id == e.id }) {
                m.end = e.on; m.updatedAt = Date()
            }
            context.insert(Campaign(plan.new))
            try? context.save()
            return .success(())
        }
    }

    /// End a real campaign today (early if before its planned last day). A default
    /// maintenance campaign then opens the next day.
    static func end(_ context: ModelContext, _ campaign: Campaign, today: Date = Date()) {
        guard !campaign.isDefault, campaign.end == nil else { return }
        let r = CampaignRules.ending(campaign.info, on: today)
        campaign.end = r.end
        campaign.endedEarly = r.early
        campaign.updatedAt = Date()
        try? context.save()
        ensureDefault(context, today: today)
    }
}
