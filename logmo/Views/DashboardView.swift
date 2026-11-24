import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @Query(sort: \DayLog.day) private var logs: [DayLog]

    @State private var window = 7
    @State private var range = 30

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var snaps: [DaySnapshot] { logs.map(\.snapshot) }

    var body: some View {
        let streak = Metrics.streak(snaps, today: today)
        let comp = Metrics.compliance(snaps, today: today, windowDays: window)
        let trend = Metrics.weightTrend(snaps, through: today, smoothingDays: smoothing)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    streakCard(streak)
                    complianceCard(comp)
                    weightCard(trend)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
        }
    }

    // MARK: Streak
    private func streakCard(_ s: (current: Int, longest: Int)) -> some View {
        Card(title: "Streak") {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(s.current)").font(.system(size: 44, weight: .bold, design: .rounded))
                    Text(s.current == 1 ? "day" : "days").foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Longest").font(.caption).foregroundStyle(.secondary)
                    Text("\(s.longest) days").font(.title3.weight(.semibold))
                }
            }
            Text("A day counts when anything is logged.").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Compliance
    private func complianceCard(_ c: Compliance) -> some View {
        Card(title: "Logging compliance") {
            Picker("Window", selection: $window) {
                Text("7 days").tag(7); Text("30 days").tag(30)
            }.pickerStyle(.segmented)

            HStack {
                Text("\(Int((c.rate * 100).rounded()))%").font(.system(size: 36, weight: .bold, design: .rounded))
                Text("\(c.daysLogged) of \(c.windowDays) days logged").foregroundStyle(.secondary)
            }
            ForEach(Tracker.allCases) { t in
                HStack {
                    Text(t.title).frame(width: 80, alignment: .leading).font(.subheadline)
                    ProgressView(value: c.rate(for: t))
                    Text("\(c.perTracker[t, default: 0])/\(c.windowDays)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    // MARK: Weight
    private func weightCard(_ trend: [TrendPoint]) -> some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range, to: today)!
        let shown = trend.filter { $0.date >= cutoff }
        let change = Metrics.trendChange(trend, overDays: 7)

        return Card(title: "Weight trend") {
            Picker("Range", selection: $range) {
                Text("30d").tag(30); Text("90d").tag(90); Text("1y").tag(365)
            }.pickerStyle(.segmented)

            if let last = trend.last {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.1f", unit.fromKg(last.trendKg))).font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(unit.rawValue).foregroundStyle(.secondary)
                    Spacer()
                    if let change {
                        let v = unit.fromKg(change) - unit.fromKg(0)
                        Text(String(format: "%+.2f %@ / 7d", v, unit.rawValue))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    } else {
                        Text("7-day change needs a week of history").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if shown.isEmpty {
                ContentUnavailableView("No weigh-ins yet", systemImage: "scalemass",
                                       description: Text("Log your weight to see the trend."))
            } else {
                Chart {
                    ForEach(shown) { p in
                        if let w = p.weightKg {
                            PointMark(x: .value("Date", p.date), y: .value("Weight", unit.fromKg(w)))
                                .foregroundStyle(.secondary).symbolSize(24)
                        }
                        LineMark(x: .value("Date", p.date), y: .value("Trend", unit.fromKg(p.trendKg)))
                            .foregroundStyle(Color.accentColor).interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
                Text("Dots: weigh-ins. Line: \(smoothing)-day smoothed trend.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
