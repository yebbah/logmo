import Foundation

/// When the app should nudge: set up a first campaign, finish the setup steps, close a finished campaign,
/// complete today's required trackers. Pure rules, no SwiftData.
enum SetupRules {
    enum Step: String, CaseIterable, Identifiable {
        case campaign, goals, firstLog
        var id: String { rawValue }
        var title: String {
            switch self {
            case .campaign: "Start a campaign"
            case .goals: "Set your weekly goals"
            case .firstLog: "Log your first day"
            }
        }
    }

    /// True when no real (non-default) campaign is running or upcoming.
    static func needsCampaign(_ campaigns: [CampaignInfo], today: Date, calendar cal: Calendar = .current) -> Bool {
        !campaigns.contains { !$0.isDefault && ($0.end.map { cal.startOfDay(for: $0) >= cal.startOfDay(for: today) } ?? true) }
    }

    static func done(_ step: Step, campaigns: [CampaignInfo], hasConfirmedGoals: Bool, logCount: Int,
                     today: Date, calendar cal: Calendar = .current) -> Bool {
        switch step {
        case .campaign: !needsCampaign(campaigns, today: today, calendar: cal)
        case .goals: hasConfirmedGoals
        case .firstLog: logCount > 0
        }
    }

    /// The first step still to do, nil when set up.
    static func next(campaigns: [CampaignInfo], hasConfirmedGoals: Bool, logCount: Int,
                     today: Date, calendar cal: Calendar = .current) -> Step? {
        Step.allCases.first { !done($0, campaigns: campaigns, hasConfirmedGoals: hasConfirmedGoals, logCount: logCount, today: today, calendar: cal) }
    }

    /// A real campaign whose planned days have all passed but which nobody has closed.
    static func isFinished(_ c: CampaignInfo, today: Date, calendar cal: Calendar = .current) -> Bool {
        !c.isDefault && c.end == nil && CampaignRules.daysLeft(c, today: today, calendar: cal) == 0
    }
}

/// Which required trackers are complete in the day being edited.
extension DayDraft {
    var completeTrackers: Set<Tracker> {
        var s: Set<Tracker> = []
        if !weight.isEmpty { s.insert(.weight) }
        if !calories.isEmpty && !protein.isEmpty && !fat.isEmpty && !carbs.isEmpty { s.insert(.food) }
        if !water.isEmpty { s.insert(.water) }
        if !steps.isEmpty { s.insert(.steps) }
        if Rating.allCases.allSatisfy({ ratings[$0] != nil || ($0 == .performance && performanceNA) }) { s.insert(.checkIn) }
        return s
    }
}
