import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @AppStorage(SettingsKey.required) private var requiredRaw = RequiredTrackers.defaultRaw
    @AppStorage("campaignFilter") private var filterRaw = "current"      // current | overall | <campaign id>
    @AppStorage("historyWeeks") private var historyWeeks = 4
    @Query(sort: \DayLog.day) private var logs: [DayLog]
    @Query private var weekGoals: [WeekGoal]
    @Query(sort: \Campaign.number) private var campaigns: [Campaign]

    @State private var window = 7
    @State private var showGoals = false

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }

    var body: some View {
        let snaps = logs.map(\.snapshot)
        let timeline = GoalTimeline(weekGoals)
        let required = RequiredTrackers.parse(requiredRaw)
        let infos = campaigns.map(\.info)
        let trend = Metrics.weightTrend(snaps, through: today, smoothingDays: smoothing)
        let selected = selectedCampaign(infos)
        let scope = scopeFor(selected, snaps)

        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        if needsGoals(timeline) { goalsBanner(timeline) }
                        campaignPicker(infos)
                        campaignCard(selected, scope, trend, infos)
                        todayCard(snaps, timeline)
                        streaksCard(snaps, timeline)
                        complianceCard(Metrics.compliance(snaps, today: today, windowDays: window,
                                                          required: required, timeline: timeline)).id("compliance")
                        PerformanceCard(snaps: snaps, trend: trend, scope: scope).id("performance")
                        WeightChartCard(title: "Weigh-ins and trend", trend: trend, snaps: snaps, scope: scope,
                                        smoothing: smoothing).id("weight")
                        RateCard(trend: trend, scope: scope).id("rate")
                        StepsCaloriesCard(snaps: snaps, scope: scope).id("steps")
                        BiofeedbackBarsCard(snaps: snaps, scope: scope).id("bio")
                        ProteinDonutCard(snaps: snaps, timeline: timeline, scope: scope)
                        OverallJourneyCard(trend: trend).id("overall")
                        historyCard(snaps, timeline)
                    }
                    .padding()
                }
                .onAppear {
                    CampaignStore.ensureDefault(context)
                    #if DEBUG
                    // Debug aid for screenshots: -scrollTo compliance|performance|weight|rate|steps|bio|overall
                    if let id = UserDefaults.standard.string(forKey: "scrollTo") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(id, anchor: .top) }
                    }
                    #endif
                }
            }
            .background(theme.bg)
            .navigationTitle("Dashboard")
            .sheet(isPresented: $showGoals) { GoalsSheet() }
        }
    }

    // MARK: Campaign filter

    private func selectedCampaign(_ infos: [CampaignInfo]) -> CampaignInfo? {
        switch filterRaw {
        case "overall": return nil
        case "current": return CampaignRules.campaign(for: today, in: infos)
        default:
            return infos.first { $0.id.uuidString == filterRaw } ?? CampaignRules.campaign(for: today, in: infos)
        }
    }

    /// Everything on the dashboard below the picker is limited to this range, except
    /// streaks, compliance, goals and the overall journey, which are about "now" or "all time".
    private func scopeFor(_ c: CampaignInfo?, _ snaps: [DaySnapshot]) -> DateScope {
        if let c { return DateScope(start: c.start, end: min(c.end ?? today, today)) }
        let first = snaps.map { cal.startOfDay(for: $0.date) }.min() ?? today
        return DateScope(start: first, end: today)
    }

    private func campaignPicker(_ infos: [CampaignInfo]) -> some View {
        let current = CampaignRules.campaign(for: today, in: infos)
        return HStack {
            Text("Showing").foregroundStyle(theme.muted)
            Spacer()
            Picker("Campaign", selection: $filterRaw) {
                Text("Current\(current.map { " · #\($0.number) \($0.kind.title)" } ?? "")").tag("current")
                Text("Overall (all time)").tag("overall")
                ForEach(infos.sorted { $0.number > $1.number }) { c in
                    Text("#\(c.number) \(c.kind.title)\(c.isDefault ? " (default)" : "")").tag(c.id.uuidString)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
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

    // MARK: Goals banner

    /// Sunday is when goals get set for the coming week; also prompt if none exist yet.
    private func needsGoals(_ t: GoalTimeline) -> Bool {
        if t.byWeek.isEmpty { return true }
        let isSunday = cal.component(.weekday, from: today) == 1
        let next = cal.date(byAdding: .day, value: 7, to: Metrics.weekStart(of: today))!
        return isSunday && t.byWeek[next] == nil
    }

    private func goalsBanner(_ t: GoalTimeline) -> some View {
        Button { showGoals = true } label: {
            HStack {
                Image(systemName: "target")
                VStack(alignment: .leading) {
                    Text(t.byWeek.isEmpty ? "Set your weekly goals" : "Set goals for next week")
                        .font(.headline)
                    Text(t.byWeek.isEmpty ? "Calories, protein, steps and water." : "It's Sunday: plan the week ahead.")
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

    // MARK: Today + this week

    private func todayCard(_ snaps: [DaySnapshot], _ t: GoalTimeline) -> some View {
        let ws = Metrics.weekStart(of: today)
        let goals = t.goals(forWeekStarting: ws)
        let todays = snaps.first { cal.isDate($0.date, inSameDayAs: today) }
        let status = Metrics.dayGoalStatus(todays, goals: goals)
        let week = Metrics.weekStatus(snaps, weekStart: ws, goals: goals, today: today)

        return Card(title: "Goals") {
            if goals == nil {
                Text("No goals set yet.").foregroundStyle(theme.muted)
            } else {
                Text("Today").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
                goalRow("Protein", value: todays?.proteinG, goal: goals?.proteinDaily, unit: "g", met: status.protein)
                goalRow("Steps", value: todays?.steps, goal: goals?.stepsDaily, unit: "", met: status.steps)
                goalRow("Water", value: todays?.waterMl, goal: goals?.waterDailyMl, unit: "ml", met: status.water)
                if !(goals?.hasDailyGoals ?? false) { Text("No daily goals set.").font(.caption).foregroundStyle(theme.muted) }

                Divider()
                Text("This week").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
                weekRow(week)
            }
            Button("Edit goals") { showGoals = true }.font(.subheadline)
        }
    }

    private func goalRow(_ title: String, value: Int?, goal: Int?, unit: String, met: Bool?) -> some View {
        Group {
            if let goal {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                        Spacer()
                        Text("\((value ?? 0).formatted()) / \(goal.formatted()) \(unit)")
                            .font(.subheadline).monospacedDigit().foregroundStyle(theme.muted)
                        statusIcon(met == true ? true : nil)
                    }
                    ProgressView(value: min(Double(value ?? 0) / Double(max(goal, 1)), 1))
                        .tint(met == true ? theme.good : theme.accent)
                }
            }
        }
    }

    private func weekRow(_ w: WeekStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let goal = w.goal {
                HStack {
                    Text("Calories")
                    Spacer()
                    Text("avg \(Int((w.average ?? 0).rounded()).formatted()) / \(Int((w.dailyTarget ?? 0).rounded()).formatted()) kcal")
                        .font(.subheadline).monospacedDigit().foregroundStyle(theme.muted)
                    switch w.outcome {
                    case .met: statusIcon(true)
                    case .missed: statusIcon(false)
                    default: statusIcon(nil)
                    }
                }
                ProgressView(value: min((w.average ?? 0) / max(w.dailyTarget ?? 1, 1), 1))
                    .tint(offTarget(w) ? theme.bad : (w.outcome == .met ? theme.good : theme.accent))
                Text(weekCaption(w, goal)).font(.caption).foregroundStyle(theme.muted)
            } else {
                Text("No weekly calorie goal set.").font(.caption).foregroundStyle(theme.muted)
            }
        }
    }

    /// Average currently on the wrong side of the daily-equivalent target.
    private func offTarget(_ w: WeekStatus) -> Bool {
        guard let avg = w.average, let target = w.dailyTarget else { return false }
        return w.atOrUnder ? avg > target : avg < target
    }

    private func weekCaption(_ w: WeekStatus, _ goal: Int) -> String {
        let days = "\(w.daysWithCalories) of 7 days logged"
        guard let avg = w.average, let target = w.dailyTarget else { return "No calories logged yet · \(days)" }
        let diff = Int(abs(avg - target).rounded())
        let side = w.atOrUnder ? (avg <= target ? "under" : "over") : (avg >= target ? "over" : "under")
        return "\(diff.formatted()) kcal/day \(side) target (\(goal.formatted()) ÷ 7) · \(days)"
    }

    private func statusIcon(_ ok: Bool?) -> some View {
        Image(systemName: ok == true ? "checkmark.circle.fill" : ok == false ? "xmark.circle.fill" : "circle")
            .foregroundStyle(ok == true ? theme.good : ok == false ? theme.bad : theme.muted)
    }

    // MARK: Streaks

    private func streaksCard(_ snaps: [DaySnapshot], _ t: GoalTimeline) -> some View {
        let log = Metrics.streak(snaps, today: today)
        let daily = Metrics.goalStreak(snaps, timeline: t, today: today)
        let weekly = Metrics.weeklyStreak(snaps, timeline: t, today: today)
        return Card(title: "Streaks") {
            HStack(alignment: .top, spacing: 12) {
                streakTile("Logging", log.current, log.longest, "days")
                streakTile("Daily goals", daily.current, daily.longest, "days")
                streakTile("Weekly goal", weekly.current, weekly.longest, "weeks")
            }
            Text("Logging: any entry. Daily goals: protein, steps and water all met. Weekly goal: finished weeks within the calorie goal. Streaks run across campaigns.")
                .font(.caption).foregroundStyle(theme.muted)
        }
    }

    private func streakTile(_ title: String, _ current: Int, _ longest: Int, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(theme.muted)
            Text("\(current)").font(.system(size: 34, weight: .bold, design: .rounded))
            Text(current == 1 ? String(unit.dropLast()) : unit).font(.caption).foregroundStyle(theme.muted)
            Text("best \(longest)").font(.caption2).foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Compliance

    private func complianceCard(_ c: Compliance) -> some View {
        Card(title: "Compliance") {
            Picker("Window", selection: $window) {
                Text("7 days").tag(7); Text("30 days").tag(30)
            }.pickerStyle(.segmented)

            HStack {
                Text("\(Int((c.rate * 100).rounded()))%").font(.system(size: 36, weight: .bold, design: .rounded))
                Text("\(c.compliedDays) of \(c.windowDays) days complied").foregroundStyle(theme.muted)
            }
            Text("Complied = everything required is fully logged, the daily goals are met, and the week's average calories are on target.")
                .font(.caption).foregroundStyle(theme.muted)
            ForEach(Tracker.allCases) { t in
                HStack {
                    Text(t.title).frame(width: 80, alignment: .leading).font(.subheadline)
                    ProgressView(value: c.rate(for: t))
                    Text("\(c.perTracker[t, default: 0])/\(c.windowDays)")
                        .font(.caption).monospacedDigit().foregroundStyle(theme.muted)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Text("Bars show days each was fully logged.").font(.caption2).foregroundStyle(theme.muted)
        }
    }

    // MARK: Recent history

    private func historyCard(_ snaps: [DaySnapshot], _ t: GoalTimeline) -> some View {
        let map = Dictionary(snaps.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let days = (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
        let thisWeek = Metrics.weekStart(of: today)
        let weeks = (0..<historyWeeks).reversed().map { cal.date(byAdding: .day, value: -7 * $0, to: thisWeek)! }

        return Card(title: "Recent") {
            Text("Daily goals, last 7 days").font(.caption).foregroundStyle(theme.muted)
            HStack {
                ForEach(days, id: \.self) { d in
                    let goals = t.goals(forWeekStarting: Metrics.weekStart(of: d))
                    let st = Metrics.dayGoalStatus(map[d], goals: goals)
                    let ok: Bool? = (goals?.hasDailyGoals ?? false)
                        ? (st.allMet ? true : (d == today && map[d] == nil ? nil : false)) : nil
                    VStack(spacing: 4) {
                        statusIcon(ok)
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(theme.muted)
                    }.frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text("Weekly calorie goal").font(.caption).foregroundStyle(theme.muted)
                Spacer()
                Picker("Weeks", selection: $historyWeeks) {
                    Text("4 weeks").tag(4); Text("8 weeks").tag(8); Text("12 weeks").tag(12)
                }.pickerStyle(.menu)
            }.padding(.top, 4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 10) {
                ForEach(weeks, id: \.self) { ws in
                    let st = Metrics.weekStatus(snaps, weekStart: ws, goals: t.goals(forWeekStarting: ws), today: today)
                    VStack(spacing: 4) {
                        statusIcon(st.outcome == .met ? true : st.outcome == .missed ? false : nil)
                        Text(ws.formatted(.dateTime.day().month(.abbreviated))).font(.caption2).foregroundStyle(theme.muted)
                    }
                }
            }
        }
    }
}

struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.border, lineWidth: 1))
    }
}
