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
    @Query(sort: \Campaign.number) private var campaigns: [Campaign]

    @State private var window = 7

    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }

    var body: some View {
        let snaps = logs.map(\.snapshot)
        let timeline = GoalTimeline(weekGoals, campaigns: campaigns.map(\.info))
        let required = RequiredTrackers.parse(requiredRaw)
        let trend = Metrics.weightTrend(snaps, through: today, smoothingDays: smoothing)

        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        streaksCard(snaps, timeline).id("streaks")
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
                    // Debug aid for screenshots: -scrollTo compliance|journey
                    if let id = UserDefaults.standard.string(forKey: "scrollTo") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(id, anchor: .top) }
                    }
                    #endif
                }
            }
            .background(theme.bg)
            .navigationTitle("Streaks")
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
                           "Consecutive finished weeks (Monday to Sunday) in which every weekly goal was met: average calories, steps when set as a weekly average, and workout days. The week in progress neither extends nor breaks it.")
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

    // MARK: Compliance

    private func complianceCard(_ c: Compliance) -> some View {
        Card(title: "Compliance", trailing: {
            InfoButton(title: "Compliance",
                       text: "A day is complied when everything required is fully logged, the daily goals are met, and the week's goals are on track: average calories, steps when set as a weekly average, and workout days still reachable. Required trackers are chosen in Settings. Today counts in the total and turns green once everything for it is done.")
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
        let firstLogged = snaps.map { cal.startOfDay(for: $0.date) }.min()
        return Card(title: "Daily goals, last 7 days") {
            HStack {
                ForEach(days, id: \.self) { d in
                    let goals = t.goals(forDay: d)                 // the goals of the campaign this day belongs to
                    let st = Metrics.dayGoalStatus(map[d], goals: goals)
                    let beforeStart = firstLogged.map { d < $0 } ?? true   // before the first logged day: nothing was tracked
                    let ok: Bool? = (goals?.hasDailyGoals ?? false) && !beforeStart
                        ? (st.allMet ? true : (d == today && map[d] == nil ? nil : false)) : nil
                    VStack(spacing: 4) {
                        StatusIcon(ok: ok)
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(theme.muted)
                    }.frame(maxWidth: .infinity)
                }
            }
            Text("Weigh-in logged, and protein, steps and water all met. A hollow circle is today (still open) or a day before you started logging.")
                .font(.caption2).foregroundStyle(theme.muted)
        }
    }

    private func weeklyHistoryCard(_ snaps: [DaySnapshot], _ t: GoalTimeline) -> some View {
        let thisWeek = Metrics.weekStart(of: today)
        let weeks = (0..<historyWeeks).reversed().map { cal.date(byAdding: .day, value: -7 * $0, to: thisWeek)! }
        return Card(title: "Weekly goals", trailing: {
            Picker("Weeks", selection: $historyWeeks) {
                Text("4w").tag(4); Text("8w").tag(8); Text("12w").tag(12)
            }.pickerStyle(.segmented).frame(width: 150)
        }) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 12) {
                ForEach(weeks, id: \.self) { ws in
                    let outcome = Metrics.weeklyOutcome(snaps, weekStart: ws, goals: t.goals(forWeekStarting: ws), today: today)
                    VStack(spacing: 4) {
                        StatusIcon(ok: outcome == .met ? true : outcome == .missed ? false : nil)
                        Text(ws.formatted(.dateTime.day().month(.abbreviated))).font(.system(size: 10)).foregroundStyle(theme.muted)
                    }
                }
            }
            Text("A week counts when all its weekly goals are met: calories, weekly-average steps, workout days. Weeks start on Monday. A hollow circle is a week still open or without weekly goals.")
                .font(.caption2).foregroundStyle(theme.muted)
        }
    }
}
