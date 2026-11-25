import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @AppStorage(SettingsKey.required) private var requiredRaw = RequiredTrackers.defaultRaw
    @AppStorage(SettingsKey.bioOverlay) private var bioOn = false
    @AppStorage(SettingsKey.bioShown) private var bioShownRaw = Rating.allCases.map(\.rawValue).joined(separator: ",")
    @Query(sort: \DayLog.day) private var logs: [DayLog]
    @Query private var weekGoals: [WeekGoal]

    @State private var window = 7
    @State private var range = 30
    @State private var showGoals = false

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var bioShown: Set<String> { Set(bioShownRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        let snaps = logs.map(\.snapshot)
        let timeline = GoalTimeline(weekGoals)
        let required = RequiredTrackers.parse(requiredRaw)

        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    if needsGoals(timeline) { goalsBanner(timeline) }
                    todayCard(snaps, timeline)
                    streaksCard(snaps, timeline)
                    complianceCard(Metrics.compliance(snaps, today: today, windowDays: window,
                                                      required: required, timeline: timeline)).id("compliance")
                    historyCard(snaps, timeline, required).id("history")
                    weightCard(snaps).id("weight")
                }
                .padding()
            }
            .onAppear {
                #if DEBUG
                // Debug aid for screenshots: -scrollTo compliance|history|weight
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
            Text("Logging: any entry. Daily goals: protein, steps and water all met. Weekly goal: finished weeks within the calorie goal.")
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

    private func historyCard(_ snaps: [DaySnapshot], _ t: GoalTimeline, _ required: Set<Tracker>) -> some View {
        let map = Dictionary(snaps.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let days = (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
        let thisWeek = Metrics.weekStart(of: today)
        let weeks = (0..<4).reversed().map { cal.date(byAdding: .day, value: -7 * $0, to: thisWeek)! }

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
            Text("Weekly calorie goal, last 4 weeks").font(.caption).foregroundStyle(theme.muted).padding(.top, 4)
            HStack {
                ForEach(weeks, id: \.self) { ws in
                    let st = Metrics.weekStatus(snaps, weekStart: ws, goals: t.goals(forWeekStarting: ws), today: today)
                    VStack(spacing: 4) {
                        statusIcon(st.outcome == .met ? true : st.outcome == .missed ? false : nil)
                        Text(ws.formatted(.dateTime.day().month(.abbreviated))).font(.caption2).foregroundStyle(theme.muted)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Weight + biofeedback

    private func weightCard(_ snaps: [DaySnapshot]) -> some View {
        let trend = Metrics.weightTrend(snaps, through: today, smoothingDays: smoothing)
        let cutoff = cal.date(byAdding: .day, value: -range, to: today)!
        let shown = trend.filter { $0.date >= cutoff }
        let change = Metrics.trendChange(trend, overDays: 7)

        return Card(title: "Weight trend") {
            Picker("Range", selection: $range) {
                Text("30d").tag(30); Text("90d").tag(90); Text("1y").tag(365)
            }.pickerStyle(.segmented)

            if let last = trend.last {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.1f", unit.fromKg(last.trendKg))).font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(unit.rawValue).foregroundStyle(theme.muted)
                    Spacer()
                    if let change {
                        Text(String(format: "%+.2f %@ / 7d", unit.fromKg(change) - unit.fromKg(0), unit.rawValue))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
                    } else {
                        Text("7-day change needs a week of history").font(.caption).foregroundStyle(theme.muted)
                    }
                }
            }

            Toggle("Show biofeedback", isOn: $bioOn)

            if bioOn {
                let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(Rating.allCases) { r in
                        let on = bioShown.contains(r.rawValue)
                        Button { toggle(r) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: on ? "checkmark.square.fill" : "square")
                                Text(r.title).font(.caption).lineLimit(1)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .foregroundStyle(on ? theme.color(for: r) : theme.muted)
                            .background((on ? theme.color(for: r) : theme.muted).opacity(0.12), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }

            if shown.isEmpty {
                ContentUnavailableView("No weigh-ins yet", systemImage: "scalemass",
                                       description: Text("Log your weight to see the trend."))
            } else {
                weightChart(shown, snaps, cutoff)
            }
        }
    }

    private func toggle(_ r: Rating) {
        var s = bioShown
        if s.contains(r.rawValue) { s.remove(r.rawValue) } else { s.insert(r.rawValue) }
        bioShownRaw = Rating.allCases.map(\.rawValue).filter(s.contains).joined(separator: ",")
    }

    private func weightChart(_ shown: [TrendPoint], _ snaps: [DaySnapshot], _ cutoff: Date) -> some View {
        // Ratings (1–5) are drawn on the weight axis by mapping 1…5 onto its visible range;
        // a second axis on the right labels them 1–5.
        let ys = shown.flatMap { p in [unit.fromKg(p.trendKg)] + (p.weightKg.map { [unit.fromKg($0)] } ?? []) }
        let rawLo = ys.min() ?? 0, rawHi = ys.max() ?? 1
        let pad = max((rawHi - rawLo) * 0.1, 0.5)
        let lo = rawLo - pad, hi = rawHi + pad
        func mapRating(_ r: Double) -> Double { lo + (r - 1) / 4 * (hi - lo) }

        let active = bioOn ? Rating.allCases.filter { bioShown.contains($0.rawValue) } : []
        let series: [(Rating, [ValuePoint])] = active.map { r in
            (r, Metrics.ratingTrend(snaps, rating: r.rawValue, through: today)
                .filter { $0.date >= cutoff })
        }

        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(shown) { p in
                    if let w = p.weightKg {
                        PointMark(x: .value("Date", p.date), y: .value("Weight", unit.fromKg(w)))
                            .foregroundStyle(theme.muted).symbolSize(24)
                    }
                    LineMark(x: .value("Date", p.date), y: .value("Trend", unit.fromKg(p.trendKg)),
                             series: .value("Series", "weight"))
                        .foregroundStyle(theme.accent).interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                }
                ForEach(series, id: \.0) { r, points in
                    ForEach(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value(r.title, mapRating(p.trend)),
                                 series: .value("Series", r.rawValue))
                            .foregroundStyle(theme.color(for: r)).interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            .chartYScale(domain: lo...hi)
            .chartYAxis {
                AxisMarks(position: .leading)
                AxisMarks(position: .trailing, values: bioOn ? [1.0, 2, 3, 4, 5].map(mapRating) : []) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                    AxisValueLabel {
                        if let y = v.as(Double.self) { Text("\(Int(((y - lo) / (hi - lo) * 4 + 1).rounded()))") }
                    }
                }
            }
            .frame(height: 220)

            Text(bioOn
                 ? "Left axis: weight (\(unit.rawValue)), thick line is the \(smoothing)-day trend. Right axis: biofeedback 1–5, 7-day smoothed. Higher isn't always better; see each rating's meaning on the Log screen."
                 : "Dots: weigh-ins. Line: \(smoothing)-day smoothed trend.")
                .font(.caption).foregroundStyle(theme.muted)
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
