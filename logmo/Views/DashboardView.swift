import SwiftUI
import SwiftData
import Charts

/// The Dashboard tab: everything here follows the "Showing" campaign filter.
/// Streaks, goals, compliance and the all-time journey live on the Streaks tab.
struct DashboardView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var nav
    @AppStorage("setupDismissedOn") private var setupDismissedOn = ""        // yyyy-MM-dd the setup card was last put off
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @AppStorage("campaignFilter") private var filterRaw = "current"      // current | overall | <campaign id>
    @Query(sort: \DayLog.day) private var logs: [DayLog]
    @Query private var weekGoals: [WeekGoal]
    @Query(sort: \Campaign.number) private var campaigns: [Campaign]

    @State private var goalsTarget: GoalsTarget?
    @State private var planCampaign: CampaignInfo?
    @State private var suggestCampaign: CampaignInfo?
    @State private var pendingGoals: GoalsTarget?      // "Edit first": opened once the suggestion sheet has dismissed
    @State private var startWeightFor: Campaign?
    @AppStorage("startWeightDismissedOn") private var startWeightDismissedOn = ""
    @State private var editUpcoming: Campaign?
    @AppStorage("closingDismissed") private var closingDismissed = ""      // "<campaign id>|<yyyy-MM-dd>" the closing-soon card was put off

    struct GoalsTarget: Identifiable { var campaign: CampaignInfo; var week: Date?; var prefill: GoalSet? = nil; var id: UUID { campaign.id } }

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }

    var body: some View {
        let snaps = logs.map(\.snapshot)
        let infos = campaigns.map(\.info)
        let timeline = GoalTimeline(weekGoals, campaigns: infos)
        let seeds = CampaignRules.trendSeeds(infos)
        let trend = Metrics.weightTrend(snaps, through: today, smoothingDays: smoothing, seeds: seeds)
        let selected = selectedCampaign(infos)
        let scope = scopeFor(selected, snaps)

        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        weekHeadline(infos)
                        setupCard(infos)
                        finishedCard(infos)
                        closingCard(infos)
                        startWeightCard()
                        campaignPicker(infos)
                        campaignCard(selected, scope, trend, infos)
                        if let gc = goalCampaign(selected, infos) {
                            let explicit = PlanStore.explicitWeeks(weekGoals, campaignID: gc.id)
                            let rawPrompt = PlanRules.prompt(gc, hasAnyGoals: weekGoals.contains { $0.campaignID == gc.id },
                                                             explicit: explicit, today: today)
                            // The setup card already asks for goals, so don't ask twice.
                            let prompt: PlanPrompt = (rawPrompt == .setGoals && setupStep(infos) != nil && !setupDismissedToday) ? .none : rawPrompt
                            PlanPromptBanner(prompt: prompt, onKeep: { keep(prompt, gc) }, onChange: { change(prompt, gc) },
                                             onSuggest: { suggestCampaign = gc })
                            GoalsCard(campaign: gc, snaps: snaps, timeline: timeline, explicitWeeks: explicit,
                                      onEdit: { goalsTarget = GoalsTarget(campaign: gc, week: nil) },
                                      onPlan: { planCampaign = gc },
                                      onSuggest: { suggestCampaign = gc }).id("goals")
                        }
                        PerformanceCard(snaps: snaps, trend: trend, scope: scope).id("performance")
                        WeightChartCard(title: "Weigh-ins and trend", trend: trend, snaps: snaps, scope: scope,
                                        smoothing: smoothing, timeline: timeline).id("weight")
                        MaintenanceCard(snaps: snaps, timeline: timeline, scope: scope, smoothing: smoothing, seeds: seeds, profile: MaintenanceProfile.load()).id("maintenance")
                        BodyCompositionCard(logs: logs, scope: scope, unit: unit).id("body")
                        WeeklyRateCard(trend: trend, scope: scope, unit: unit).id("weekly")
                        RateCard(trend: trend, scope: scope).id("rate")
                        StepsCaloriesCard(snaps: snaps, scope: scope).id("steps")
                        BiofeedbackBarsCard(snaps: snaps, scope: scope).id("bio")
                    }
                    .padding()
                }
                .onAppear {
                    CampaignStore.tidy(context)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let text = CampaignRules.daysLeftBadge(infos, today: today) {
                        Button { nav.tab = 3 } label: {
                            // An HStack, not a Label: the toolbar turns a Label into just its icon.
                            HStack(spacing: 5) { Image(systemName: "flag.checkered"); Text(text) }
                                .font(.footnote.weight(.semibold)).foregroundStyle(theme.accent).fixedSize()
                        }
                        .accessibilityLabel("\(text) in the current campaign. Opens Campaigns.")
                    }
                }
            }
            .sheet(item: $goalsTarget) { t in GoalsSheet(campaign: t.campaign, week: t.week, prefill: t.prefill) }
            .sheet(item: $startWeightFor) { StartWeightSheet(campaign: $0) }
            .sheet(item: $suggestCampaign, onDismiss: {
                if let p = pendingGoals { pendingGoals = nil; goalsTarget = p }
            }) { c in
                SuggestSheet(campaign: c) { goals, week in pendingGoals = GoalsTarget(campaign: c, week: week, prefill: goals) }
            }
.navigationDestination(item: $planCampaign) { WeeklyPlanView(campaign: $0) }
            .sheet(item: $editUpcoming) { m in
                EditUpcomingForm(campaign: m, earliest: CampaignRules.earliestUpcomingStart(existing: infos, excluding: m.id, today: today))
            }
        }
    }

    /// Which week we are in: the campaign's week and this week's dates.
    private func weekHeadline(_ infos: [CampaignInfo]) -> some View {
        let h = CampaignRules.weekHeadline(infos, today: today)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(h.title).font(.title3.weight(.bold))
            Text(h.dates).font(.subheadline).foregroundStyle(theme.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Setup and finished-campaign prompts

    private var todayKey: String { today.formatted(.iso8601.year().month().day()) }
    private var setupDismissedToday: Bool { setupDismissedOn == todayKey }

    private func setupStep(_ infos: [CampaignInfo]) -> SetupRules.Step? {
        SetupRules.next(campaigns: infos, hasConfirmedGoals: weekGoals.contains { $0.confirmed }, logCount: logs.count, today: today)
    }

    /// First-run checklist, and the nudge to configure a campaign when none is running. "Not now" hides it for today.
    @ViewBuilder private func setupCard(_ infos: [CampaignInfo]) -> some View {
        if let next = setupStep(infos), !setupDismissedToday {
            let needsCampaign = SetupRules.needsCampaign(infos, today: today)
            let steps = SetupRules.Step.allCases.map { s in
                (s.title, SetupRules.done(s, campaigns: infos, hasConfirmedGoals: weekGoals.contains { $0.confirmed },
                                          logCount: logs.count, today: today))
            }
            PromptCard(tint: theme.accent, icon: "flag.checkered",
                       title: needsCampaign ? "Set up a campaign" : "Get set up",
                       text: needsCampaign ? "No campaign is running. Pick a cut, bulk or maintenance, with dates and a target."
                                           : "A couple of steps left to get the most from logmo.",
                       steps: steps,
                       actions: [.init(title: "Not now", run: { setupDismissedOn = todayKey }),
                                 .init(title: needsCampaign ? "Set up campaign" : next.title, filled: true, run: { runSetup(next, infos) })])
        }
    }

    private func runSetup(_ step: SetupRules.Step, _ infos: [CampaignInfo]) {
        switch step {
        case .campaign: nav.openNewCampaign = true; nav.tab = 3
        case .goals:
            if let c = CampaignRules.campaign(for: today, in: infos) { goalsTarget = GoalsTarget(campaign: c, week: nil) }
        case .firstLog: nav.tab = 2
        }
    }

    /// A real campaign past its planned last day, still open: close it, extend it, or start the next.
    @ViewBuilder private func finishedCard(_ infos: [CampaignInfo]) -> some View {
        if let c = infos.first(where: { SetupRules.isFinished($0, today: today) }),
           let model = campaigns.first(where: { $0.id == c.id }) {
            PromptCard(tint: theme.warn, icon: "flag.checkered.2.crossed", title: "\(c.name) has finished",
                       text: "Its \(c.plannedWeeks ?? 0) weeks are over. Close it to see how it went, or keep going.",
                       actions: [.init(title: "Extend 2 weeks", run: { if !CampaignStore.extend(context, model, byWeeks: 2) { editUpcoming = upcomingCampaign } }),
                                 .init(title: "End & see results", filled: true, run: { CampaignStore.finish(context, model); nav.tab = 3 })])
        }
    }

    /// A real campaign that is running or about to start without a starting weight: ask for one, so the trend is predictable.
    @ViewBuilder private func startWeightCard() -> some View {
        if let m = campaigns.first(where: { !$0.isDefault && $0.end == nil && $0.startWeightKg == nil }), startWeightDismissedOn != todayKey {
            PromptCard(tint: theme.accent, icon: "scalemass", title: "Add a starting weight for \(m.info.name)",
                       text: "Your weight trend starts from it on the campaign's first day, so the trend behaves predictably. It is filled in with your current trend weight.",
                       actions: [.init(title: "Not now", run: { startWeightDismissedOn = todayKey }),
                                 .init(title: "Set it", filled: true, run: { startWeightFor = m })])
        }
    }

    private var upcomingCampaign: Campaign? {
        campaigns.first { !$0.isDefault && $0.end == nil && CampaignRules.isUpcoming($0.info, today: today) }
    }

    /// A week or less before a running campaign's planned end: offer to extend it, or if another campaign is
    /// already planned, say so and offer to move that one's start date.
    @ViewBuilder private func closingCard(_ infos: [CampaignInfo]) -> some View {
        if let c = infos.first(where: { CampaignRules.closingIn($0, today: today) != nil }),
           let days = CampaignRules.closingIn(c, today: today), let model = campaigns.first(where: { $0.id == c.id }),
           closingDismissed != "\(c.id)|\(todayKey)" {
            let end = CampaignRules.plannedEnd(c)?.formatted(.dateTime.day().month(.abbreviated)) ?? ""
            let notNow = PromptCard.Action(title: "Not now", run: { closingDismissed = "\(c.id)|\(todayKey)" })
            if let next = upcomingCampaign {
                PromptCard(tint: theme.accent, icon: "calendar.badge.clock",
                           title: "\(c.name) closes in \(days) day\(days == 1 ? "" : "s")",
                           text: "It ends on \(end). Your next campaign, \(next.info.name), starts \(next.start.formatted(.dateTime.day().month(.abbreviated))). Do you want to move its start date?",
                           actions: [notNow, .init(title: "Move start date", filled: true, run: { editUpcoming = next })])
            } else {
                PromptCard(tint: theme.accent, icon: "calendar.badge.clock",
                           title: "\(c.name) closes in \(days) day\(days == 1 ? "" : "s")",
                           text: "It ends on \(end). Want to keep going? Extend it, or let it close and see how it went.",
                           actions: [notNow,
                                     .init(title: "Extend 2 weeks", run: { CampaignStore.extend(context, model, byWeeks: 2) }),
                                     .init(title: "Extend 4 weeks", filled: true, run: { CampaignStore.extend(context, model, byWeeks: 4) })])
            }
        }
    }

    // MARK: Goals

    /// Goals belong to a campaign. The card follows the filter; with "Overall" it shows the
    /// campaign running today, since today's and this week's goals only exist there.
    private func goalCampaign(_ selected: CampaignInfo?, _ infos: [CampaignInfo]) -> CampaignInfo? {
        selected ?? CampaignRules.campaign(for: today, in: infos)
    }

    /// "Keep them" / "Same as this week": the user decided the carried-over goals stand.
    private func keep(_ p: PlanPrompt, _ c: CampaignInfo) {
        switch p {
        case .carriedOver(let w), .planNext(let w): PlanStore.confirm(context, campaignID: c.id, week: w)
        default: break
        }
    }

    private func change(_ p: PlanPrompt, _ c: CampaignInfo) {
        switch p {
        case .carriedOver(let w), .planNext(let w): goalsTarget = GoalsTarget(campaign: c, week: w)
        case .setGoals: goalsTarget = GoalsTarget(campaign: c, week: nil)
        case .none: break
        }
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
        func name(_ c: CampaignInfo) -> String { CampaignRules.pickerName(c, today: today) }
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
                    Text("Current\(current.map { " · " + CampaignRules.pickerName($0, today: today) } ?? "")").tag("current")
                    Text("Overall (all time)").tag("overall")
                    ForEach(infos.sorted { $0.number > $1.number }) { c in
                        Text(CampaignRules.pickerName(c, today: today)).tag(c.id.uuidString)
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
        let noCampaign = c == nil && filterRaw != "overall"       // "Current" with nothing running: days outside a campaign belong to none
        return Card(title: c?.name ?? (noCampaign ? "No campaign running" : "Overall")) {
            if let c {
                let upcoming = CampaignRules.isUpcoming(c, today: today)
                let number = "#\(c.number) \(c.kind.title)\(c.isDefault ? " (default)" : "")"
                Text("\(number) · \(CampaignRules.periodText(c, today: today))" + (c.endedEarly ? " · ended early" : ""))
                    .font(.caption).foregroundStyle(theme.muted)

                if upcoming {
                    let n = CampaignRules.daysUntilStart(c, today: today)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n)").font(.system(size: 44, weight: .bold, design: .rounded))
                        Text(n == 1 ? "day until it starts" : "days until it starts").foregroundStyle(theme.muted)
                        Spacer()
                        Text("\(c.plannedWeeks ?? 0) weeks").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
                    }
                    Text("The current campaign carries on until then.").font(.caption).foregroundStyle(theme.muted)
                } else if c.plannedWeeks != nil, c.end == nil, let left = CampaignRules.daysLeft(c, today: today) {
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
            } else if noCampaign {
                Text("Every campaign has a start and an end, and none covers today. Start one to set goals and follow its progress. Meanwhile the charts below show all your data.")
                    .font(.subheadline).foregroundStyle(theme.muted)
                Button { nav.openNewCampaign = true; nav.tab = 3 } label: { Text("Start a campaign").fontWeight(.semibold).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
            } else {
                let first = trend.first?.date
                Text(first.map { "All data since \($0.formatted(date: .abbreviated, time: .omitted)), across \(infos.count) campaign\(infos.count == 1 ? "" : "s")" }
                     ?? "No data yet.").font(.subheadline).foregroundStyle(theme.muted)
            }
        }
    }
}
