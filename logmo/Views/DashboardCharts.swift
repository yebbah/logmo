import SwiftUI
import Charts

/// Inclusive date range a dashboard section is limited to (a campaign, or everything).
struct DateScope: Equatable {
    var start: Date
    var end: Date
}

private func fmt(_ v: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", v) }
private func signed(_ v: Double, _ digits: Int = 2) -> String { String(format: "%+.\(digits)f", v) }

#if DEBUG
/// Debug aid for screenshots: `-expand weight|rate|steps|overall` opens that chart full screen.
private func debugExpand(_ name: String, _ flag: Binding<Bool>) {
    if UserDefaults.standard.string(forKey: "expand") == name {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { flag.wrappedValue = true }
    }
}
#endif

// MARK: - Weigh-ins vs trend

/// Range picker, numbers, biofeedback switch and the chart itself. Used inline in a card
/// and, with `compact`, in the landscape full-screen view; both share the same settings.
struct WeightChartBody: View {
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.bioOverlay) private var bioOn = false
    @AppStorage(SettingsKey.bioShown) private var bioShownRaw = Rating.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage("weightRange") private var range = 30          // days; 0 = the whole scope
    @AppStorage(SettingsKey.trackCycle) private var trackCycle = false
    @AppStorage(SettingsKey.trackSick) private var trackSick = false

    let trend: [TrendPoint]
    let snaps: [DaySnapshot]
    let scope: DateScope
    let smoothing: Int
    let timeline: GoalTimeline
    let height: CGFloat?
    let compact: Bool

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var bioShown: Set<String> { Set(bioShownRaw.split(separator: ",").map(String.init)) }
    private var cal: Calendar { .current }

    private var from: Date {
        guard range > 0 else { return scope.start }
        let d = cal.date(byAdding: .day, value: -(range - 1), to: scope.end)!
        return max(scope.start, d)
    }
    private var shown: [TrendPoint] { trend.filter { $0.date >= from && $0.date <= scope.end } }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            Picker("Range", selection: $range) {
                Text("14d").tag(14); Text("30d").tag(30); Text("90d").tag(90); Text("All").tag(0)
            }.pickerStyle(.segmented)

            if let last = shown.last {
                HStack(alignment: .firstTextBaseline) {
                    Text(fmt(unit.fromKg(last.trendKg)))
                        .font(.system(size: compact ? 20 : 34, weight: .bold, design: .rounded))
                    Text("\(unit.rawValue) trend").foregroundStyle(theme.muted).font(compact ? .caption : .body)
                    Spacer()
                    if let w = shown.last(where: { $0.weightKg != nil })?.weightKg {
                        Text("last weigh-in \(fmt(unit.fromKg(w)))").font(.caption).foregroundStyle(theme.muted)
                    }
                }
            }

            Toggle("Show biofeedback", isOn: $bioOn)
            if bioOn { chips }

            if shown.isEmpty {
                ContentUnavailableView("No weigh-ins here", systemImage: "scalemass",
                                       description: Text("Log your weight to see the trend."))
            } else {
                chart.chartHeight(height)
                legend
            }
        }
    }

    @ViewBuilder private var chips: some View {
        let items = ForEach(Rating.allCases) { r in
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
        if compact {
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { items } }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) { items }
        }
    }

    private func toggle(_ r: Rating) {
        var s = bioShown
        if s.contains(r.rawValue) { s.remove(r.rawValue) } else { s.insert(r.rawValue) }
        bioShownRaw = Rating.allCases.map(\.rawValue).filter(s.contains).joined(separator: ",")
    }

    private var weighIns: [TrendPoint] { shown.filter { $0.weightKg != nil } }
    /// Weigh-in values are labelled when there's room; trend values only on the last point
    /// unless there are very few points, so labels don't pile up.
    private var labelled: Bool { shown.count <= (compact ? 31 : 15) }
    private var labelAllTrend: Bool { shown.count <= 15 }

    private var yRange: (lo: Double, hi: Double) {
        var ys = shown.map { unit.fromKg($0.trendKg) }
        ys += weighIns.compactMap { $0.weightKg.map { unit.fromKg($0) } }
        let lo = ys.min() ?? 0, hi = ys.max() ?? 1
        let pad = max((hi - lo) * 0.12, 0.5)
        return (lo - pad, hi + pad)
    }

    private var chart: some View {
        let (lo, hi) = yRange
        func mapRating(_ r: Double) -> Double { lo + (r - 1) / 4 * (hi - lo) }
        let active = bioOn ? Rating.allCases.filter { bioShown.contains($0.rawValue) } : []
        let bio: [(Rating, [ValuePoint])] = active.map { r in
            (r, Metrics.ratingTrend(snaps, rating: r.rawValue, through: scope.end).filter { $0.date >= from && $0.date <= scope.end })
        }

        return Chart {
            ForEach(weighIns) { p in
                if let w = p.weightKg {
                    LineMark(x: .value("Date", p.date), y: .value("Weigh-in", unit.fromKg(w)), series: .value("S", "weighin"))
                        .foregroundStyle(theme.muted.opacity(0.75)).lineStyle(StrokeStyle(lineWidth: 1.5))
                    PointMark(x: .value("Date", p.date), y: .value("Weigh-in", unit.fromKg(w)))
                        .foregroundStyle(p.isSick && trackSick ? theme.sick : (p.onPeriod && trackCycle ? theme.bad : theme.muted))
                        .symbolSize((p.isSick && trackSick) || (p.onPeriod && trackCycle) ? 60 : 28)
                        .annotation(position: .top, spacing: 2) {
                            if labelled { Text(fmt(unit.fromKg(w))).font(.system(size: 9)).foregroundStyle(theme.muted) }
                        }
                }
            }
            ForEach(shown) { p in
                LineMark(x: .value("Date", p.date), y: .value("Trend", unit.fromKg(p.trendKg)), series: .value("S", "trend"))
                    .foregroundStyle(theme.accent).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 3))
            }
            ForEach(shown) { p in
                if labelAllTrend || p.id == shown.last?.id {
                    PointMark(x: .value("Date", p.date), y: .value("Trend", unit.fromKg(p.trendKg)))
                        .foregroundStyle(theme.accent).symbolSize(20)
                        .annotation(position: .bottom, spacing: 2) {
                            Text(fmt(unit.fromKg(p.trendKg), 2)).font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.accent)
                        }
                }
            }
            // Days marked as on the cycle: a red dot on the trend as well as the weigh-in.
            ForEach(shown.filter { $0.onPeriod && trackCycle }) { p in
                PointMark(x: .value("Date", p.date), y: .value("Trend", unit.fromKg(p.trendKg)))
                    .foregroundStyle(theme.bad).symbolSize(60)
            }
            // Days marked sick: a yellow dot on the trend too.
            ForEach(shown.filter { $0.isSick && trackSick }) { p in
                PointMark(x: .value("Date", p.date), y: .value("Trend", unit.fromKg(p.trendKg)))
                    .foregroundStyle(theme.sick).symbolSize(60)
            }
            ForEach(bio, id: \.0) { r, points in
                ForEach(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value(r.title, mapRating(p.trend)), series: .value("S", r.rawValue))
                        .foregroundStyle(theme.color(for: r)).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
        }
        .chartYScale(domain: lo...hi)
        .chartYAxis {
            AxisMarks(position: .leading)
            AxisMarks(position: .trailing, values: bioOn ? [1.0, 2, 3, 4, 5].map(mapRating) : []) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                AxisValueLabel { if let y = v.as(Double.self) { Text("\(Int(((y - lo) / (hi - lo) * 4 + 1).rounded()))") } }
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                HStack(spacing: 6) { Circle().fill(theme.muted).frame(width: 8, height: 8); Text("Weigh-ins") }
                HStack(spacing: 6) { Capsule().fill(theme.accent).frame(width: 16, height: 4); Text("Trend (\(smoothing)-day smoothing)") }
                if trackCycle && shown.contains(where: \.onPeriod) {
                    HStack(spacing: 6) { Circle().fill(theme.bad).frame(width: 8, height: 8); Text("On period") }
                }
                if trackSick && shown.contains(where: \.isSick) {
                    HStack(spacing: 6) { Circle().fill(theme.sick).frame(width: 8, height: 8); Text("Sick") }
                }
            }.font(.caption).foregroundStyle(theme.muted)
            if bioOn && !compact {
                Text("Right axis: biofeedback 1–5, 7-day smoothed. Higher isn't always better; see each rating's meaning on the Log screen.")
                    .font(.caption2).foregroundStyle(theme.muted)
            }
        }
    }
}

struct WeightChartCard: View {
    let title: String
    let trend: [TrendPoint]
    let snaps: [DaySnapshot]
    let scope: DateScope
    let smoothing: Int
    let timeline: GoalTimeline
    @State private var full = false

    var body: some View {
        Card(title: title, trailing: { ExpandButton { full = true } }) {
            WeightChartBody(trend: trend, snaps: snaps, scope: scope, smoothing: smoothing, timeline: timeline,
                            height: 240, compact: false)
        }
        .landscapeCover(isPresented: $full) {
            FullScreenFrame(title: title) {
                WeightChartBody(trend: trend, snaps: snaps, scope: scope, smoothing: smoothing, timeline: timeline,
                                height: nil, compact: true)
            }
        }
        #if DEBUG
        .onAppear { debugExpand("weight", $full) }
        #endif
    }
}

// MARK: - Rate of change

struct StepsCaloriesCard: View {
    @Environment(\.theme) private var theme
    let snaps: [DaySnapshot]
    let scope: DateScope
    @State private var full = false

    private struct Bar: Identifiable { var id: String; var day: Date; var metric: String; var value: Double }

    var body: some View {
        let cal = Calendar.current
        let from = max(scope.start, cal.date(byAdding: .day, value: -13, to: scope.end)!)
        let map = Dictionary(snaps.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let days = Insights.days(from: from, to: scope.end)
        let maxSteps = Double(days.compactMap { map[$0]?.steps }.max() ?? 0)
        let maxCal = Double(days.compactMap { map[$0]?.calories }.max() ?? 0)
        let yMax = max(maxSteps, 1)
        let factor = maxCal > 0 ? yMax / maxCal : 1                         // calories drawn on the steps axis
        let week = Insights.averages(snaps, from: max(scope.start, cal.date(byAdding: .day, value: -6, to: scope.end)!), to: scope.end)

        var bars: [Bar] = []
        for d in days {
            if let s = map[d]?.steps { bars.append(Bar(id: "s\(d.timeIntervalSince1970)", day: d, metric: "Steps", value: Double(s))) }
            if let c = map[d]?.calories { bars.append(Bar(id: "c\(d.timeIntervalSince1970)", day: d, metric: "Calories", value: Double(c) * factor)) }
        }

        return Card(title: "Steps and calories", trailing: { if !bars.isEmpty { ExpandButton { full = true } } }) {
            HStack(spacing: 24) {
                tile(week.calories.map { "\(Int($0.rounded()).formatted()) cals" } ?? "—", "Average calories, past 7 days")
                tile(week.steps.map { "\(Int($0.rounded()).formatted()) steps" } ?? "—", "Average steps, past 7 days")
            }
            if bars.isEmpty {
                Text("No steps or calories logged in this period.").foregroundStyle(theme.muted)
            } else {
                chart(bars, yMax, factor).chartHeight(200)
                Text("Left axis: steps. Right axis: calories. Last 14 days.").font(.caption).foregroundStyle(theme.muted)
            }
        }
        .landscapeCover(isPresented: $full) {
            FullScreenFrame(title: "Steps and calories") { chart(bars, yMax, factor).chartHeight(nil) }
        }
        #if DEBUG
        .onAppear { debugExpand("steps", $full) }
        #endif
    }

    private func chart(_ bars: [Bar], _ yMax: Double, _ factor: Double) -> some View {
        Chart(bars) { b in
            BarMark(x: .value("Day", b.day, unit: .day), y: .value("Value", b.value))
                .position(by: .value("Metric", b.metric))
                .foregroundStyle(by: .value("Metric", b.metric))
        }
        .chartForegroundStyleScale(["Steps": theme.accent.opacity(0.55), "Calories": theme.accent])
        .chartYScale(domain: 0...(yMax * 1.05))
        .chartYAxis {
            AxisMarks(position: .leading)
            AxisMarks(position: .trailing, values: [0, 0.25, 0.5, 0.75, 1].map { $0 * yMax }) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                AxisValueLabel { if let y = v.as(Double.self) { Text(Int((y / factor).rounded()).formatted()) } }
            }
        }
    }

    private func tile(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(caption).font(.caption2).foregroundStyle(theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Biofeedback bars + protein donut

struct BiofeedbackBarsCard: View {
    @Environment(\.theme) private var theme
    let snaps: [DaySnapshot]
    let scope: DateScope

    var body: some View {
        let from = max(scope.start, Calendar.current.date(byAdding: .day, value: -6, to: scope.end)!)
        Card(title: "Biofeedback, last 7 days") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Rating.allCases) { r in
                    let series = Insights.ratingSeries(snaps, rating: r.rawValue, from: from, to: scope.end)
                    miniCard(r, series)
                }
            }
        }
    }

    private func barColor(_ r: Rating) -> Color {
        switch r.betterWhen {
        case .higher: theme.accent
        case .lower: theme.color(for: .fatigue)
        case .neutral: theme.muted
        }
    }

    private func miniCard(_ r: Rating, _ series: [(date: Date, value: Int?)]) -> some View {
        let avg = Insights.average(series.map { $0.value })
        return VStack(alignment: .leading, spacing: 6) {
            Text(r.title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            Chart {
                ForEach(Array(series.enumerated()), id: \.offset) { i, p in
                    if let v = p.value {
                        BarMark(x: .value("Day", i), y: .value("Rating", v)).foregroundStyle(barColor(r)).cornerRadius(2)
                    }
                }
            }
            .chartYScale(domain: 0...5)
            .chartXScale(domain: -0.5...(Double(max(series.count, 1)) - 0.5))
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 70)
            Text(avg.map { "Average \(fmt($0)) of 5" } ?? "No data").font(.caption).foregroundStyle(theme.muted)
            Text("(\(r.betterNote))").font(.caption2).foregroundStyle(theme.muted)
        }
        .padding(10)
        .background(theme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Recent performance numbers

struct PerformanceCard: View {
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    let snaps: [DaySnapshot]
    let trend: [TrendPoint]
    let scope: DateScope

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    var body: some View {
        let cal = Calendar.current
        let from14 = max(scope.start, cal.date(byAdding: .day, value: -13, to: scope.end)!)
        let a = Insights.averages(snaps, from: from14, to: scope.end)
        let inScope = trend.filter { $0.date >= scope.start && $0.date <= scope.end }
        let overall = (inScope.first != nil && inScope.last != nil) ? inScope.last!.trendKg - inScope.first!.trendKg : nil

        return Card(title: "Recent performance") {
            HStack(alignment: .top, spacing: 12) {
                tile(overall.map { "\(signed(unit.fromKg($0) - unit.fromKg(0))) \(unit.rawValue)" } ?? "—", "Overall change in this period (trend)")
                tile(a.calories.map { "\(Int($0.rounded()).formatted())" } ?? "—", "Average calories, last 14 days")
            }
            HStack(alignment: .top, spacing: 12) {
                tile(a.proteinG.map { "\(Int($0.rounded())) g" } ?? "—", "Average protein, last 14 days")
                tile(a.steps.map { "\(Int($0.rounded()).formatted())" } ?? "—", "Average steps, last 14 days")
            }
            Divider()
            Text("Weight change from the trend").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
            HStack(alignment: .top, spacing: 12) {
                ForEach([7, 14, 21], id: \.self) { n in
                    let c = Metrics.trendChange(inScope, overDays: n)
                    tile(c.map { "\(signed(unit.fromKg($0) - unit.fromKg(0))) \(unit.rawValue)" } ?? "—", "In \(n) days")
                }
            }
        }
    }

    private func tile(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
            Text(caption).font(.caption2).foregroundStyle(theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Overall journey (always everything, regardless of campaign)

struct OverallJourneyCard: View {
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    let trend: [TrendPoint]
    @State private var full = false

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    var body: some View {
        Card(title: "Overall weight journey", trailing: { if !trend.isEmpty { ExpandButton { full = true } } }) {
            if let first = trend.first, let last = trend.last {
                let change = unit.fromKg(last.trendKg) - unit.fromKg(first.trendKg)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(signed(change)) \(unit.rawValue)").font(.system(size: 28, weight: .bold, design: .rounded))
                    Spacer()
                    Text("since \(first.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(theme.muted)
                }
                Text("\(fmt(unit.fromKg(first.trendKg))) → \(fmt(unit.fromKg(last.trendKg))) \(unit.rawValue), across all campaigns")
                    .font(.caption).foregroundStyle(theme.muted)
                chart.chartHeight(170)
                legend
            } else {
                Text("Log your first weight to start your journey.").foregroundStyle(theme.muted)
            }
        }
        .landscapeCover(isPresented: $full) {
            FullScreenFrame(title: "Overall weight journey") {
                chart.chartHeight(nil)
                legend
            }
        }
        #if DEBUG
        .onAppear { debugExpand("overall", $full) }
        #endif
    }

    private var chart: some View {
        Chart {
            ForEach(trend.filter { $0.weightKg != nil }) { p in
                if let w = p.weightKg {
                    LineMark(x: .value("Date", p.date), y: .value("Weigh-in", unit.fromKg(w)), series: .value("S", "w"))
                        .foregroundStyle(theme.muted.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            ForEach(trend) { p in
                LineMark(x: .value("Date", p.date), y: .value("Trend", unit.fromKg(p.trendKg)), series: .value("S", "t"))
                    .foregroundStyle(theme.accent).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2.5))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) { Capsule().fill(theme.muted.opacity(0.6)).frame(width: 16, height: 3); Text("Weigh-ins") }
            HStack(spacing: 6) { Capsule().fill(theme.accent).frame(width: 16, height: 4); Text("Trend") }
        }.font(.caption).foregroundStyle(theme.muted)
    }
}


/// Body fat and lean mass from Apple Health, over the period being shown: the latest reading and how it moved.
struct BodyCompositionCard: View {
    @Environment(\.theme) private var theme
    let logs: [DayLog]
    let scope: DateScope
    let unit: WeightUnit

    var body: some View {
        let inScope = logs.filter { $0.day >= scope.start && $0.day <= scope.end }.sorted { $0.day < $1.day }
        let fat = inScope.compactMap { $0.healthBodyFat }
        let lean = inScope.compactMap { $0.healthLeanKg }.map { unit.fromKg($0) }
        if !fat.isEmpty || !lean.isEmpty {
            Card(title: "Body composition") {
                HStack(alignment: .top, spacing: 16) {
                    if let last = fat.last { tile(String(format: "%.1f%%", last), "Body fat", change: fat.count > 1 ? last - fat[0] : nil, suffix: "%") }
                    if let last = lean.last { tile(String(format: "%.1f %@", last, unit.rawValue), "Lean mass", change: lean.count > 1 ? last - lean[0] : nil, suffix: " \(unit.rawValue)") }
                }
                Text("From Apple Health. Change is since the first reading in this period, so you can see whether a cut or bulk is fat or muscle.")
                    .font(.caption).foregroundStyle(theme.muted)
            }
        }
    }

    private func tile(_ value: String, _ caption: String, change: Double?, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(caption).font(.caption).foregroundStyle(theme.muted)
            if let change { Text(String(format: "%+.1f%@ since first reading", change, suffix)).font(.caption2).foregroundStyle(theme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Estimated maintenance calories (TDEE), laid out like the workbook: the estimate now, your goal and what you eat against it,
/// the smoothed estimate over time, and a weekly table of goal, eaten and maintenance.
struct MaintenanceCard: View {
    @Environment(\.theme) private var theme
    let snaps: [DaySnapshot]
    let timeline: GoalTimeline
    let scope: DateScope
    let smoothing: Int
    var seeds: [Date: Double] = [:]
    let profile: MaintenanceProfile?

    private var cal: Calendar { .current }

    var body: some View {
        let estimate = Maintenance.estimate(snaps, through: scope.end, smoothingDays: smoothing, seeds: seeds, profile: profile)
        let hasData = snaps.contains { $0.weightKg != nil || $0.calories != nil }
        if hasData {
            Card(title: "Estimated maintenance", trailing: { statusChip(estimate) }) {
                if let e = estimate { content(e) } else { empty }
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder private func statusChip(_ e: MaintenanceEstimate?) -> some View {
        if let e {
            let (text, color): (String, Color) = e.source == .formula ? ("Formula", theme.muted) : (e.status == .updating ? ("Updating", theme.good) : ("Holding", theme.warn))
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 3).background(color.opacity(0.14), in: Capsule())
        }
    }

    private var empty: some View {
        let counts = snaps.filter { $0.calories != nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("Not enough yet").font(.subheadline.weight(.semibold))
            Text("Maintenance is worked out from your weight trend and what you eat. It starts after four weeks of logging in all, counted from your first day across every campaign, so a new campaign that carries on from an earlier one keeps using the history already there. It also needs a weigh-in on at least five of the last ten days and calories on at least seven (\(counts) days with calories so far). Or add your height, age, sex and activity in Settings → About you for a formula estimate in the meantime.")
                .font(.caption).foregroundStyle(theme.muted)
        }
    }

    @ViewBuilder private func content(_ e: MaintenanceEstimate) -> some View {
        let goal = timeline.goals(forDay: scope.end)?.caloriesWeekly.map { Int((Double($0) / 7).rounded()) }
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(e.kcalPerDay.formatted()).font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("kcal a day").foregroundStyle(theme.muted)
                }
                Text(e.source == .formula ? "From your height, age, sex and activity. Your own logs will replace this."
                     : (e.status == .updating ? "From your weight trend and what you eat." : "Held from earlier: recent weigh-ins or calorie logs are too few to move it."))
                    .font(.caption).foregroundStyle(theme.muted)
            }
            let week = Maintenance.sevenDayAverage(snaps, through: scope.end)
            if let goal {
                Text("Your goal of \(goal.formatted()) a day is \(relation(goal, e.kcalPerDay)).")
                    .font(.subheadline.weight(.semibold))
            }
            if e.source == .trend, let f = e.formulaKcal {
                Text("A formula from your height, age, sex and activity gives \(f.formatted()) as a cross-check.").font(.caption).foregroundStyle(theme.muted)
            }
            if let goal, let seen = week ?? e.intakeKcal, Maintenance.intakeLooksIncomplete(intake: seen, goal: goal) {
                Label {
                    Text("You've logged about \(Int((Double(seen) / Double(goal) * 100).rounded()))% of your goal (\(seen.formatted()) a day). If some days are only partly logged, maintenance is underestimated, because this is built from what you log.")
                        .font(.caption)
                } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warn) }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.warn.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            }
            if e.series.compactMap(\.tdee).count >= 2 { chart(e, goal: goal) }
            weekly(e)
            Text(e.source == .trend
                 ? "The estimate is built from your smoothed intake (\(e.intakeKcal.map { $0.formatted() } ?? "–") a day), which moves slowly; the table shows what you actually ate each week. Weight is smoothed like the trend line, and the weekly change in it is turned into calories (about 1,100 a day for each kg a week) and taken off what you eat. It holds while weigh-ins or calorie logs are missing, and never treats a missing day as zero."
                 : "A formula (Mifflin-St Jeor times your activity) is only a starting point.")
                .font(.caption).foregroundStyle(theme.muted)
        }
    }

    /// "440 below maintenance" and the percentage.
    private func relation(_ goal: Int, _ maintenance: Int) -> String {
        let diff = goal - maintenance
        if abs(diff) < 25 { return "about maintenance" }
        let pct = Int((abs(Double(diff)) / Double(maintenance) * 100).rounded())
        return "\(abs(diff).formatted()) kcal \(diff < 0 ? "below" : "above") it (\(pct)%)"
    }

    private func chart(_ e: MaintenanceEstimate, goal: Int?) -> some View {
        let pts = e.series.filter { $0.date >= scope.start && $0.date <= scope.end }
        let values = pts.compactMap(\.tdee) + pts.compactMap(\.intake) + (goal.map { [Double($0)] } ?? [])
        let lo = (values.min() ?? 1500) - 100, hi = (values.max() ?? 3000) + 100
        return Chart {
            ForEach(pts) { p in
                if let i = p.intake {
                    LineMark(x: .value("Date", p.date), y: .value("Eating", i), series: .value("S", "eating"))
                        .foregroundStyle(theme.muted.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                if let t = p.tdee {
                    LineMark(x: .value("Date", p.date), y: .value("Maintenance", t), series: .value("S", "tdee"))
                        .foregroundStyle(theme.accent).lineStyle(StrokeStyle(lineWidth: 3)).interpolationMethod(.monotone)
                }
            }
            if let goal {
                RuleMark(y: .value("Goal", goal)).foregroundStyle(theme.good).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
        .chartYScale(domain: lo...hi)
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 170)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 12) {
                legend(theme.accent, "Maintenance"); legend(theme.muted, "Eating"); if goal != nil { legend(theme.good, "Goal") }
            }
            .font(.caption2).foregroundStyle(theme.muted).offset(y: 22)
        }
        .padding(.bottom, 22)
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Capsule().fill(c).frame(width: 12, height: 3); Text(t) }
    }

    /// One row per week, newest first, like the workbook's weekly anchors.
    @ViewBuilder private func weekly(_ e: MaintenanceEstimate) -> some View {
        let rows = weeklyRows(e)
        if !rows.isEmpty {
            VStack(spacing: 8) {
                HStack {
                    Text("Week of").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Goal").frame(width: 62, alignment: .trailing)
                    Text("Eaten").frame(width: 62, alignment: .trailing)
                    Text("Maintenance").frame(width: 92, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(theme.muted)
                ForEach(rows, id: \.week) { r in
                    HStack {
                        Text(r.week.formatted(.dateTime.day().month(.abbreviated))).frame(maxWidth: .infinity, alignment: .leading)
                        Text(r.goal.map { $0.formatted() } ?? "–").frame(width: 62, alignment: .trailing)
                        Text(r.eaten.map { $0.formatted() } ?? "–").frame(width: 62, alignment: .trailing)
                        Text(r.maintenance.map { $0.formatted() } ?? "–").frame(width: 92, alignment: .trailing).fontWeight(.semibold)
                    }
                    .font(.subheadline).monospacedDigit()
                    Divider()
                }
            }
        }
    }

    private struct WeekRow { var week: Date; var goal: Int?; var eaten: Int?; var maintenance: Int? }

    private func weeklyRows(_ e: MaintenanceEstimate) -> [WeekRow] {
        let thisWeek = Metrics.weekStart(of: scope.end)
        let map = Dictionary(snaps.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        var rows: [WeekRow] = []
        for k in 0..<6 {
            guard let ws = cal.date(byAdding: .day, value: -7 * k, to: thisWeek), ws >= Metrics.weekStart(of: scope.start) else { break }
            let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: ws) }.filter { $0 <= scope.end }
            let cals = days.compactMap { map[$0]?.calories }
            let eaten = cals.isEmpty ? nil : Int((Double(cals.reduce(0, +)) / Double(cals.count)).rounded())
            let goal = timeline.goals(forWeekStarting: ws)?.caloriesWeekly.map { Int((Double($0) / 7).rounded()) }
            let m = e.series.last(where: { $0.tdee != nil && $0.date <= (days.last ?? ws) && $0.date >= ws })?.tdee.map { Int($0.rounded()) }
            if goal != nil || eaten != nil || m != nil { rows.append(WeekRow(week: ws, goal: goal, eaten: eaten, maintenance: m)) }
        }
        return rows
    }
}


/// The workbook's weekly line on the Dashboard: the trend weight at the end of each week and how it moved from the week before.
struct WeeklyRateCard: View {
    @Environment(\.theme) private var theme
    let trend: [TrendPoint]
    let scope: DateScope
    let unit: WeightUnit

    var body: some View {
        let rows = Metrics.weeklyTrendRows(trend, from: scope.start, through: scope.end)
        if !rows.isEmpty {
            Card(title: "Weekly rate of change") {
                if let latest = rows.first(where: { $0.changeKg != nil }), let kg = latest.changeKg {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%+.2f %@", unit.fromKg(latest.trendKg) - unit.fromKg(latest.trendKg - kg), unit.rawValue))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(latest.inProgress ? "so far this week" : "last full week").font(.subheadline).foregroundStyle(theme.muted)
                        Spacer()
                        if let p = latest.changePercent { Text(String(format: "%+.2f%% of body weight", p)).font(.caption).foregroundStyle(theme.muted) }
                    }
                }
                VStack(spacing: 8) {
                    HStack {
                        Text("Week").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Trend").frame(width: 78, alignment: .trailing)
                        Text("Change").frame(width: 124, alignment: .trailing)
                    }
                    .font(.caption2.weight(.semibold)).foregroundStyle(theme.muted)
                    ForEach(rows) { r in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(label(r)).font(.subheadline)
                                if r.inProgress { Text("so far").font(.caption2).foregroundStyle(theme.muted) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%.2f %@", unit.fromKg(r.trendKg), unit.rawValue)).font(.subheadline).monospacedDigit().frame(width: 78, alignment: .trailing)
                            Text(change(r)).font(.caption).monospacedDigit().foregroundStyle(r.changeKg == nil ? theme.muted : Color.primary)
                                .multilineTextAlignment(.trailing).frame(width: 124, alignment: .trailing)
                        }
                        Divider()
                    }
                }
                Text("The trend weight at the end of each week (Monday to Sunday) and how far it moved from the end of the week before. A week with no earlier trend to compare shows N/A.")
                    .font(.caption).foregroundStyle(theme.muted)
            }
        }
    }

    private func label(_ r: WeeklyTrendRow) -> String {
        let f = Date.FormatStyle().day().month(.abbreviated)
        let end = Calendar.current.date(byAdding: .day, value: 6, to: r.weekStart)!
        return "\(r.weekStart.formatted(f)) – \(end.formatted(f))"
    }

    private func change(_ r: WeeklyTrendRow) -> String {
        guard let kg = r.changeKg else { return "N/A" }
        let delta = unit.fromKg(r.trendKg) - unit.fromKg(r.trendKg - kg)
        let pct = r.changePercent.map { String(format: " · %+.2f%%", $0) } ?? ""
        return String(format: "%+.2f %@", delta, unit.rawValue) + pct
    }
}
