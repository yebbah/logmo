import SwiftUI
import SwiftData

/// The Streaks tab: consistency over time. Nothing here follows the campaign filter.
struct StreaksView: View {
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @AppStorage(SettingsKey.required) private var requiredRaw = RequiredTrackers.defaultRaw
    @AppStorage("historyWeeks") private var historyWeeks = 8
    @Query(sort: \DayLog.day) private var logs: [DayLog]
    @Query private var weekGoals: [WeekGoal]

    @State private var window = 7
    @State private var showGoals = false

    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }

    var body: some View {
        let snaps = logs.map(\.snapshot)
        let timeline = GoalTimeline(weekGoals)
        let required = RequiredTrackers.parse(requiredRaw)
        let trend = Metrics.weightTrend(snaps, through: today, smoothingDays: smoothing)

        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        streaksCard(snaps, timeline).id("streaks")
                        if needsGoals(timeline) { goalsBanner(timeline) }
                        todayCard(snaps, timeline).id("goals")
                        complianceCard(Metrics.compliance(snaps, today: today, windowDays: window,
                                                          required: required, timeline: timeline)).id("compliance")
                        dailyHistoryCard(snaps, timeline)
                        weeklyHistoryCard(snaps, timeline)
                        OverallJourneyCard(trend: trend).id("journey")
                    }
                    .padding()
                }
                .onAppear {
                    #if DEBUG
                    // Debug aid for screenshots: -scrollTo goals|compliance|journey
                    if let id = UserDefaults.standard.string(forKey: "scrollTo") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(id, anchor: .top) }
                    }
                    #endif
                }
            }
            .background(theme.bg)
            .navigationTitle("Streaks")
            .sheet(isPresented: $showGoals) { GoalsSheet() }
        }
    }

    // MARK: Streaks

    private func streaksCard(_ snaps: [DaySnapshot], _ t: GoalTimeline) -> some View {
        let log = Metrics.streak(snaps, today: today)
        let daily = Metrics.goalStreak(snaps, timeline: t, today: today)
        let weekly = Metrics.weeklyStreak(snaps, timeline: t, today: today)
        return Card(title: "Streaks") {
            HStack(alignment: .top, spacing: 12) {
                streakTile("Logging", log.current, log.longest, "days",
                           "Consecutive days with any entry logged. A day you haven't logged yet today doesn't break it. Streaks run across campaigns.")
                streakTile("Daily goals", daily.current, daily.longest, "days",
                           "Consecutive days on which your protein, steps and water goals were all met. Today doesn't break it until the day is over.")
                streakTile("Weekly goal", weekly.current, weekly.longest, "weeks",
                           "Consecutive finished weeks (Monday to Sunday) whose average daily calories were on target. The week in progress neither extends nor breaks it.")
            }
        }
    }

    private func streakTile(_ title: String, _ current: Int, _ longest: Int, _ unit: String, _ info: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(theme.muted).lineLimit(1).minimumScaleFactor(0.8)
                InfoButton(title: "\(title) streak", text: info)
            }
            Text("\(current)").font(.system(size: 34, weight: .bold, design: .rounded))
            Text(current == 1 ? String(unit.dropLast()) : unit).font(.caption).foregroundStyle(theme.muted)
            Text("best \(longest)").font(.caption2).foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text(t.byWeek.isEmpty ? "Set your weekly goals" : "Set goals for next week").font(.headline)
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
                        StatusIcon(ok: met == true ? true : nil)
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
                    StatusIcon(ok: w.outcome == .met ? true : w.outcome == .missed ? false : nil)
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

    // MARK: Compliance

    private func complianceCard(_ c: Compliance) -> some View {
        Card(title: "Compliance", trailing: {
            InfoButton(title: "Compliance",
                       text: "A day is complied when everything required is fully logged, the daily goals are met, and the week's average calories are on target. Required trackers are chosen in Settings. Today counts in the total and turns green once everything for it is done.")
        }) {
            Picker("Window", selection: $window) {
                Text("7 days").tag(7); Text("30 days").tag(30)
            }.pickerStyle(.segmented)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int((c.rate * 100).rounded()))%").font(.system(size: 36, weight: .bold, design: .rounded))
                Text("\(c.compliedDays) of \(c.windowDays) days complied").foregroundStyle(theme.muted)
            }
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

    // MARK: Daily and weekly history (two separate cards)

    private func dailyHistoryCard(_ snaps: [DaySnapshot], _ t: GoalTimeline) -> some View {
        let map = Dictionary(snaps.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let days = (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
        return Card(title: "Daily goals, last 7 days") {
            HStack {
                ForEach(days, id: \.self) { d in
                    let goals = t.goals(forWeekStarting: Metrics.weekStart(of: d))
                    let st = Metrics.dayGoalStatus(map[d], goals: goals)
                    let ok: Bool? = (goals?.hasDailyGoals ?? false)
                        ? (st.allMet ? true : (d == today && map[d] == nil ? nil : false)) : nil
                    VStack(spacing: 4) {
                        StatusIcon(ok: ok)
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(theme.muted)
                    }.frame(maxWidth: .infinity)
                }
            }
            Text("Protein, steps and water all met. A hollow circle is today, still open.")
                .font(.caption2).foregroundStyle(theme.muted)
        }
    }

    private func weeklyHistoryCard(_ snaps: [DaySnapshot], _ t: GoalTimeline) -> some View {
        let thisWeek = Metrics.weekStart(of: today)
        let weeks = (0..<historyWeeks).reversed().map { cal.date(byAdding: .day, value: -7 * $0, to: thisWeek)! }
        return Card(title: "Weekly calorie goal", trailing: {
            Picker("Weeks", selection: $historyWeeks) {
                Text("4w").tag(4); Text("8w").tag(8); Text("12w").tag(12)
            }.pickerStyle(.segmented).frame(width: 150)
        }) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 12) {
                ForEach(weeks, id: \.self) { ws in
                    let st = Metrics.weekStatus(snaps, weekStart: ws, goals: t.goals(forWeekStarting: ws), today: today)
                    VStack(spacing: 4) {
                        StatusIcon(ok: st.outcome == .met ? true : st.outcome == .missed ? false : nil)
                        Text(ws.formatted(.dateTime.day().month(.abbreviated))).font(.system(size: 10)).foregroundStyle(theme.muted)
                    }
                }
            }
            Text("Weeks start on Monday. A hollow circle is a week still open or without a calorie goal.")
                .font(.caption2).foregroundStyle(theme.muted)
        }
    }
}
