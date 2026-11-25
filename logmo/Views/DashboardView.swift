import SwiftUI
import SwiftData
import Charts

/// The Dashboard tab: everything here follows the "Showing" campaign filter.
/// Streaks, goals, compliance and the all-time journey live on the Streaks tab.
struct DashboardView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @AppStorage("campaignFilter") private var filterRaw = "current"      // current | overall | <campaign id>
    @Query(sort: \DayLog.day) private var logs: [DayLog]
    @Query private var weekGoals: [WeekGoal]
    @Query(sort: \Campaign.number) private var campaigns: [Campaign]

    @State private var showGoals = false

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }

    var body: some View {
        let snaps = logs.map(\.snapshot)
        let infos = campaigns.map(\.info)
        let timeline = GoalTimeline(weekGoals, campaigns: infos)
        let trend = Metrics.weightTrend(snaps, through: today, smoothingDays: smoothing)
        let selected = selectedCampaign(infos)
        let scope = scopeFor(selected, snaps)

        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        campaignPicker(infos)
                        campaignCard(selected, scope, trend, infos)
                        if let gc = goalCampaign(selected, infos) {
                            if CampaignRules.contains(gc, day: today) && needsGoals(gc) { goalsBanner(gc) }
                            GoalsCard(campaign: gc, snaps: snaps, timeline: timeline, onEdit: { showGoals = true }).id("goals")
                        }
                        PerformanceCard(snaps: snaps, trend: trend, scope: scope).id("performance")
                        WeightChartCard(title: "Weigh-ins and trend", trend: trend, snaps: snaps, scope: scope,
                                        smoothing: smoothing).id("weight")
                        RateCard(trend: trend, scope: scope).id("rate")
                        StepsCaloriesCard(snaps: snaps, scope: scope).id("steps")
                        BiofeedbackBarsCard(snaps: snaps, scope: scope).id("bio")
                        ProteinDonutCard(snaps: snaps, timeline: timeline, scope: scope).id("protein")
                    }
                    .padding()
                }
                .onAppear {
                    CampaignStore.ensureDefault(context)
                    #if DEBUG
                    // Debug aid for screenshots: -scrollTo goals|performance|weight|rate|steps|bio|protein
                    if let id = UserDefaults.standard.string(forKey: "scrollTo") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(id, anchor: .top) }
                    }
                    #endif
                }
            }
            .background(theme.bg)
            .navigationTitle("Dashboard")
            .sheet(isPresented: $showGoals) {
                if let gc = goalCampaign(selectedCampaign(infos), infos) { GoalsSheet(campaign: gc) }
            }
        }
    }

    // MARK: Goals

    /// Goals belong to a campaign. The card follows the filter; with "Overall" it shows the
    /// campaign running today, since today's and this week's goals only exist there.
    private func goalCampaign(_ selected: CampaignInfo?, _ infos: [CampaignInfo]) -> CampaignInfo? {
        selected ?? CampaignRules.campaign(for: today, in: infos)
    }

    /// Sunday is when goals get set for the coming week; also prompt if the campaign has none yet.
    private func needsGoals(_ c: CampaignInfo) -> Bool {
        let mine = Set(weekGoals.filter { $0.campaignID == c.id }.map(\.weekStart))
        if mine.isEmpty { return true }
        guard cal.component(.weekday, from: today) == 1 else { return false }
        let next = cal.date(byAdding: .day, value: 7, to: Metrics.weekStart(of: today))!
        let inCampaign = c.end.map { next <= Metrics.weekStart(of: $0) } ?? true
        return inCampaign && !mine.contains(next)
    }

    private func goalsBanner(_ c: CampaignInfo) -> some View {
        let none = !weekGoals.contains { $0.campaignID == c.id }
        return Button { showGoals = true } label: {
            HStack {
                Image(systemName: "target")
                VStack(alignment: .leading) {
                    Text(none ? "Set your weekly goals" : "Set goals for next week").font(.headline)
                    Text(none ? "Calories, protein, steps and water, for this campaign." : "It's Sunday: plan the week ahead.")
                        .font(.caption).foregroundStyle(theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(theme.muted)
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: Campaign filter

    private func selectedCampaign(_ infos: [CampaignInfo]) -> CampaignInfo? {
        switch filterRaw {
        case "overall": return nil
        case "current": return CampaignRules.campaign(for: today, in: infos)
        default:
            #if DEBUG
            // Debug aid for screenshots: -campaignFilter number:2
            if filterRaw.hasPrefix("number:"), let n = Int(filterRaw.dropFirst(7)), let c = infos.first(where: { $0.number == n }) { return c }
            #endif
            return infos.first { $0.id.uuidString == filterRaw } ?? CampaignRules.campaign(for: today, in: infos)
        }
    }

    /// Everything on this tab is limited to this range.
    private func scopeFor(_ c: CampaignInfo?, _ snaps: [DaySnapshot]) -> DateScope {
        if let c { return DateScope(start: c.start, end: min(c.end ?? today, today)) }
        let first = snaps.map { cal.startOfDay(for: $0.date) }.min() ?? today
        return DateScope(start: first, end: today)
    }

    private func filterLabel(_ infos: [CampaignInfo]) -> String {
        let current = CampaignRules.campaign(for: today, in: infos)
        func name(_ c: CampaignInfo) -> String { "#\(c.number) \(c.kind.title)\(c.isDefault ? " (default)" : "")" }
        switch filterRaw {
        case "overall": return "Overall (all time)"
        case "current": return "Current" + (current.map { " · " + name($0) } ?? "")
        default: return infos.first { $0.id.uuidString == filterRaw }.map(name) ?? "Current"
        }
    }

    /// Label above, and the chosen name gets the whole row, wrapping if it is long.
    private func campaignPicker(_ infos: [CampaignInfo]) -> some View {
        let current = CampaignRules.campaign(for: today, in: infos)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Showing").font(.caption.weight(.semibold)).foregroundStyle(theme.muted)
            Menu {
                Picker("Campaign", selection: $filterRaw) {
                    Text("Current\(current.map { " · #\($0.number) \($0.kind.title)" } ?? "")").tag("current")
                    Text("Overall (all time)").tag("overall")
                    ForEach(infos.sorted { $0.number > $1.number }) { c in
                        Text("#\(c.number) \(c.kind.title)\(c.isDefault ? " (default)" : "")").tag(c.id.uuidString)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(filterLabel(infos)).foregroundStyle(theme.accent)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(theme.accent)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.track, lineWidth: 1))
            }
            .accessibilityLabel("Showing campaign: \(filterLabel(infos))")
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.border, lineWidth: 1))
    }

    private func campaignCard(_ c: CampaignInfo?, _ scope: DateScope, _ trend: [TrendPoint], _ infos: [CampaignInfo]) -> some View {
        let df = Date.FormatStyle().day().month(.abbreviated)
        return Card(title: c?.title ?? "Overall") {
            if let c {
                let range = c.end.map { "\(c.start.formatted(df)) – \($0.formatted(df))" } ?? "since \(c.start.formatted(df))"
                Text(range + (c.endedEarly ? " · ended early" : "")).font(.caption).foregroundStyle(theme.muted)

                if c.plannedWeeks != nil, c.end == nil, let left = CampaignRules.daysLeft(c, today: today) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(left)").font(.system(size: 44, weight: .bold, design: .rounded))
                        Text(left == 1 ? "day left" : "days left").foregroundStyle(theme.muted)
                        Spacer()
                        Text("week \(CampaignRules.weekNumber(c, today: today)) of \(c.plannedWeeks ?? 0)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
                    }
                    let total = Double((c.plannedWeeks ?? 1) * 7)
                    ProgressView(value: min(max(1 - Double(left) / total, 0), 1))
                } else if let planned = c.plannedWeeks {
                    Text("\(planned)-week campaign" + (c.end != nil ? ", finished" : ""))
                        .font(.subheadline).foregroundStyle(theme.muted)
                } else {
                    Text("Automatic maintenance period between campaigns.").font(.subheadline).foregroundStyle(theme.muted)
                }

                if let target = c.targetWeightKg, let now = trend.last(where: { $0.date <= scope.end }) {
                    let diff = unit.fromKg(now.trendKg) - unit.fromKg(target)
                    HStack {
                        Text("Target \(String(format: "%.1f", unit.fromKg(target))) \(unit.rawValue)")
                        Spacer()
                        Text(abs(diff) < 0.05 ? "At target" : String(format: "%.1f %@ %@", abs(diff), unit.rawValue,
                                                                      diff > 0 ? "above" : "below"))
                            .foregroundStyle(theme.muted)
                    }.font(.subheadline)
                }
            } else {
                let first = trend.first?.date
                Text(first.map { "All data since \($0.formatted(date: .abbreviated, time: .omitted)), across \(infos.count) campaign\(infos.count == 1 ? "" : "s")" }
                     ?? "No data yet.").font(.subheadline).foregroundStyle(theme.muted)
            }
        }
    }
}
