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
                if !compact {
                    Divider()
                    ProteinIntakeSection(snaps: snaps, timeline: timeline, from: from, to: scope.end,
                                         rangeLabel: range == 0 ? "this period" : "the last \(range) days")
                }
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

struct RateCard: View {
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    let trend: [TrendPoint]
    let scope: DateScope
    @State private var full = false

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var points: [RatePoint] {
        Array(Insights.rateOfChange(trend).filter { $0.date >= scope.start && $0.date <= scope.end }.suffix(84))   // last 12 weeks
    }

    var body: some View {
        let pts = points
        Card(title: "Rate of change per week", trailing: { if !pts.isEmpty { ExpandButton { full = true } } }) {
            if let last = pts.last {
                let base = trend.first(where: { $0.date == last.date })?.trendKg ?? 1
                HStack(alignment: .firstTextBaseline) {
                    Text("\(signed(unit.fromKg(last.kgPerWeek) - unit.fromKg(0))) \(unit.rawValue)/wk")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(signed(last.kgPerWeek / base * 100, 2))% of body weight")
                        .font(.caption).foregroundStyle(theme.muted)
                }
                chart(pts).chartHeight(150)
                Text("Each bar: trend weight today minus 7 days earlier. Needs a week of history.")
                    .font(.caption).foregroundStyle(theme.muted)
            } else {
                Text("Needs at least a week of weigh-ins in this period.").foregroundStyle(theme.muted)
            }
        }
        .landscapeCover(isPresented: $full) {
            FullScreenFrame(title: "Rate of change per week") { chart(pts).chartHeight(nil) }
        }
        #if DEBUG
        .onAppear { debugExpand("rate", $full) }
        #endif
    }

    private func chart(_ pts: [RatePoint]) -> some View {
        Chart(pts) { p in
            BarMark(x: .value("Date", p.date, unit: .day), y: .value("Rate", unit.fromKg(p.kgPerWeek) - unit.fromKg(0)))
                .foregroundStyle(theme.accent)
            RuleMark(y: .value("Zero", 0)).foregroundStyle(theme.muted).lineStyle(StrokeStyle(lineWidth: 1))
        }
    }
}

// MARK: - Steps and calories

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

/// Protein intake for the range chosen on the weigh-ins card: days the goal was hit out of days with a goal.
struct ProteinIntakeSection: View {
    @Environment(\.theme) private var theme
    let snaps: [DaySnapshot]
    let timeline: GoalTimeline
    let from: Date
    let to: Date
    let rangeLabel: String

    private struct Slice: Identifiable { var id: String; var count: Int }

    var body: some View {
        let r = Insights.proteinDays(snaps, timeline: timeline, from: from, to: to)
        VStack(alignment: .leading, spacing: 10) {
            Text("Protein intake").font(.subheadline.weight(.semibold))
            if r.hit + r.missed == 0 {
                Text("No protein goal set for this period.").font(.subheadline).foregroundStyle(theme.muted)
            } else {
                HStack(spacing: 20) {
                    Chart([Slice(id: "Days hit", count: r.hit), Slice(id: "Days missed", count: r.missed)]) { s in
                        SectorMark(angle: .value("Days", s.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(by: .value("Result", s.id))
                    }
                    .chartForegroundStyleScale(["Days hit": theme.accent, "Days missed": theme.track])
                    .chartLegend(.hidden)
                    .frame(width: 110, height: 110)
                    .overlay { Text("\(r.hit)/\(r.hit + r.missed)").font(.title3.bold()) }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) { Circle().fill(theme.accent).frame(width: 8, height: 8); Text("Days hit") }
                        HStack(spacing: 6) { Circle().fill(theme.track).frame(width: 8, height: 8); Text("Days missed or unlogged") }
                        Text("Over \(rangeLabel)").font(.caption).foregroundStyle(theme.muted)
                    }.font(.caption)
                }
            }
        }
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
