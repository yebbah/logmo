import SwiftUI
import SwiftData
import Charts

private func fmt(_ v: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", v) }
private func whole(_ v: Double?) -> String { v.map { Int($0.rounded()).formatted() } ?? "—" }

/// The Campaigns tab: the campaign running now (with start, end, rename and goals), and a look back
/// at every campaign so far.
struct CampaignsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @AppStorage(SettingsKey.required) private var requiredRaw = RequiredTrackers.defaultRaw
    @Query(sort: \Campaign.number, order: .reverse) private var campaigns: [Campaign]
    @Query(sort: \DayLog.day) private var logs: [DayLog]
    @Query private var weekGoals: [WeekGoal]

    @State private var showNew = false
    @State private var confirmEnd = false
    @State private var confirmCancel = false
    @State private var goalsFor: CampaignInfo?
    @State private var renameTarget: Campaign?
    @State private var renameText = ""

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        let infos = campaigns.map(\.info)
        let snaps = logs.map(\.snapshot)
        let timeline = GoalTimeline(weekGoals, campaigns: infos)
        let trend = Metrics.weightTrend(snaps, through: today, smoothingDays: smoothing)
        let required = RequiredTrackers.parse(requiredRaw)
        let current = campaigns.first { CampaignRules.contains($0.info, day: today) }
        let upcoming = campaigns.first { !$0.isDefault && $0.end == nil && CampaignRules.isUpcoming($0.info, today: today) }
        let busy = campaigns.contains { !$0.isDefault && $0.end == nil }          // running or upcoming
        let report: (CampaignInfo) -> CampaignReport = { c in
            Insights.campaignReport(c, snaps: snaps, trend: trend, timeline: timeline, required: required, today: today)
        }

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let current { nowCard(current, busy: busy, upcoming: upcoming != nil, report: report(current.info)) }
                    if let upcoming { upcomingCard(upcoming) }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Look back").font(.title3.weight(.bold))
                        Spacer()
                        Text("\(campaigns.count) campaign\(campaigns.count == 1 ? "" : "s")").font(.caption).foregroundStyle(theme.muted)
                    }
                    .padding(.horizontal, 4).padding(.top, 4)

                    ForEach(campaigns) { m in
                        let r = report(m.info)
                        NavigationLink {
                            CampaignDetail(info: m.info, report: r, trend: trend)
                        } label: {
                            lookBackCard(m.info, r)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(theme.bg)
            .navigationTitle("Campaigns")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNew = true } label: { Label("New", systemImage: "plus") }
                        .disabled(busy)
                }
            }
            .onAppear { CampaignStore.ensureDefault(context) }
            .sheet(isPresented: $showNew) { NewCampaignForm(minStart: openDefaultStart) }
            .sheet(item: $goalsFor) { c in GoalsSheet(campaign: c) }
            .alert("Rename campaign", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("Label", text: $renameText)
                Button("Save") { if let m = renameTarget { CampaignStore.rename(context, m, to: renameText) }; renameTarget = nil }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            } message: { Text("Leave it empty to use the standard name.") }
        }
    }

    private var openDefaultStart: Date {
        campaigns.first { $0.isDefault && $0.end == nil }?.start ?? today
    }

    // MARK: Running now

    private func nowCard(_ m: Campaign, busy: Bool, upcoming: Bool, report: CampaignReport) -> some View {
        let c = m.info
        let real = !c.isDefault
        return Card(title: c.name, trailing: {
            Text(real ? "week \(CampaignRules.weekNumber(c, today: today)) of \(c.plannedWeeks ?? 0)" : "no campaign")
                .font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                .padding(.horizontal, 8).padding(.vertical, 3).background(theme.accent.opacity(0.12), in: Capsule())
        }) {
            Text("#\(c.number) \(c.kind.title) · \(CampaignRules.periodText(c, today: today))")
                .font(.caption).foregroundStyle(theme.muted)
            if real, let left = CampaignRules.daysLeft(c, today: today) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(left)").font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(left == 1 ? "day left" : "days left").foregroundStyle(theme.muted)
                }
                ProgressView(value: min(max(1 - Double(left) / Double((c.plannedWeeks ?? 1) * 7), 0), 1))
            } else if !real {
                Text("Maintenance since \(c.start.formatted(.dateTime.day().month(.abbreviated))). Start a campaign any time.")
                    .font(.subheadline).foregroundStyle(theme.muted)
            }
            HStack(spacing: 10) {
                if real {
                    actionButton("Edit goals") { goalsFor = c }
                    actionButton("Rename") { renameText = c.label ?? ""; renameTarget = m }
                    actionButton("End campaign", destructive: true) { confirmEnd = true }
                        .confirmationDialog("End \(c.name) today?", isPresented: $confirmEnd, titleVisibility: .visible) {
                            Button("End campaign", role: .destructive) { CampaignStore.end(context, m) }
                        } message: { Text("It stays in your history. A default maintenance campaign starts tomorrow.") }
                } else {
                    actionButton("Start a campaign", prominent: true) { showNew = true }.disabled(busy)
                    actionButton("Edit goals") { goalsFor = c }
                    actionButton("Rename") { renameText = c.label ?? ""; renameTarget = m }
                }
            }
            if !real && upcoming {
                Text("A campaign is already planned, so another can't be started yet.").font(.caption).foregroundStyle(theme.muted)
            }
        }
    }

    private func upcomingCard(_ m: Campaign) -> some View {
        let c = m.info
        let n = CampaignRules.daysUntilStart(c, today: today)
        return Card(title: "Upcoming: \(c.name)") {
            Text("#\(c.number) \(c.kind.title) · \(CampaignRules.periodText(c, today: today))").font(.caption).foregroundStyle(theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n)").font(.system(size: 36, weight: .bold, design: .rounded))
                Text(n == 1 ? "day until it starts" : "days until it starts").foregroundStyle(theme.muted)
            }
            HStack(spacing: 10) {
                actionButton("Edit goals") { goalsFor = c }
                actionButton("Rename") { renameText = c.label ?? ""; renameTarget = m }
                actionButton("Cancel it", destructive: true) { confirmCancel = true }
                    .confirmationDialog("Cancel \(c.name)?", isPresented: $confirmCancel, titleVisibility: .visible) {
                        Button("Cancel campaign", role: .destructive) { CampaignStore.cancelUpcoming(context, m) }
                    } message: { Text("It is removed, and the current campaign carries on.") }
            }
        }
    }

    private func actionButton(_ title: String, destructive: Bool = false, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .foregroundStyle(prominent ? theme.onAccent : (destructive ? theme.bad : theme.accent))
                .background(prominent ? theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(prominent ? Color.clear : theme.track, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Look back

    private func status(_ c: CampaignInfo) -> String {
        c.end == nil ? (CampaignRules.isUpcoming(c, today: today) ? "upcoming" : "running")
                     : (c.endedEarly ? "ended early" : (c.isDefault ? "closed" : "completed"))
    }

    private func lookBackCard(_ c: CampaignInfo, _ r: CampaignReport) -> some View {
        let planned = (c.plannedWeeks ?? 0) * 7
        let length = !r.started ? "starts in \(CampaignRules.daysUntilStart(c, today: today)) days"
            : (c.endedEarly && planned > 0 ? "\(r.days) of \(planned) planned days" : "\(r.days) days\(c.end == nil ? " so far" : "")")
        return Card(title: c.name, trailing: {
            HStack(spacing: 6) {
                Text(status(c)).font(.caption.weight(.semibold)).foregroundStyle(status(c) == "running" ? theme.accent : theme.muted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((status(c) == "running" ? theme.accent : theme.muted).opacity(0.12), in: Capsule())
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.muted)
            }
        }) {
            Text("#\(c.number) \(c.kind.title) · \(CampaignRules.periodText(c, today: today)) · \(length)")
                .font(.caption).foregroundStyle(theme.muted)
            if r.started {
                if let ch = r.changeKg, let a = r.startTrendKg, let b = r.endTrendKg {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(String(format: "%+.1f", unit.fromKg(ch) - unit.fromKg(0))) \(unit.rawValue)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("trend, \(fmt(unit.fromKg(a))) → \(fmt(unit.fromKg(b)))").font(.caption).foregroundStyle(theme.muted)
                        Spacer()
                        if let t = c.targetWeightKg { Text("target \(fmt(unit.fromKg(t)))").font(.caption).foregroundStyle(theme.muted) }
                    }
                } else {
                    Text("No weigh-ins").font(.subheadline).foregroundStyle(theme.muted)
                }
                HStack(alignment: .top, spacing: 10) {
                    metric("\(Int((r.compliance.rate * 100).rounded()))%", "Compliance, \(r.compliance.compliedDays) of \(r.compliance.windowDays) days")
                    metric(whole(r.averages.steps), "Average steps")
                    metric(whole(r.averages.calories), "Average calories")
                }
                Text(extraLine(r)).font(.caption).foregroundStyle(theme.muted)
            }
        }
    }

    private func extraLine(_ r: CampaignReport) -> String {
        var parts: [String] = []
        parts.append(r.weeklyGoals == 0 ? "No finished weeks with goals" : "Weekly goals \(r.weeklyGoalsMet) of \(r.weeklyGoals) weeks")
        if let w = r.workoutsPerWeek {
            let target = r.goalsAtEnd?.workoutDaysWeekly.map { " of \($0)" } ?? ""
            parts.append("Workouts \(fmt(w)) a week\(target)")
        }
        return parts.joined(separator: " · ")
    }

    private func metric(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.caption2).foregroundStyle(theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - One campaign's look back

struct CampaignDetail: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var nav
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage("campaignFilter") private var filterRaw = "current"
    @Query private var allCampaigns: [Campaign]
    @State private var labelText = ""
    @State private var loadedLabel = false

    let info: CampaignInfo
    let report: CampaignReport
    let trend: [TrendPoint]

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        let planned = (info.plannedWeeks ?? 0) * 7
        ScrollView {
            VStack(spacing: 16) {
                header(planned)
                if report.started {
                    resultCard
                    complianceCard
                    goalsCard
                    averagesCard
                }
                actionsCard
            }
            .padding()
        }
        .background(theme.bg)
        .navigationTitle("Campaign \(info.number)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !loadedLabel { labelText = info.label ?? ""; loadedLabel = true } }
        .onDisappear { saveLabel() }
    }

    // MARK: header

    private func header(_ planned: Int) -> some View {
        let st = info.end == nil ? (CampaignRules.isUpcoming(info, today: today) ? "upcoming" : "running")
                                 : (info.endedEarly ? "ended early" : (info.isDefault ? "closed" : "completed"))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(info.name).font(.system(size: 28, weight: .bold)).lineLimit(2)
                Spacer()
                Text(st).font(.caption.weight(.semibold)).foregroundStyle(theme.muted)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(theme.muted.opacity(0.12), in: Capsule())
            }
            Text("#\(info.number) \(info.kind.title) · \(CampaignRules.periodText(info, today: today))")
                .font(.footnote).foregroundStyle(theme.muted)
            if !report.started {
                Text("Starts in \(CampaignRules.daysUntilStart(info, today: today)) days. Nothing to look back on yet.")
                    .font(.footnote).foregroundStyle(theme.muted)
            } else if planned > 0 {
                let weeks = report.days / 7, extra = report.days % 7
                Text("Planned \(info.plannedWeeks ?? 0) weeks, \(info.end == nil ? "so far" : "ran") \(weeks) week\(weeks == 1 ? "" : "s")\(extra > 0 ? " and \(extra) day\(extra == 1 ? "" : "s")" : "")")
                    .font(.footnote).foregroundStyle(theme.muted)
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: result

    private var resultCard: some View {
        Card(title: "Result") {
            if let ch = report.changeKg, let a = report.startTrendKg, let b = report.endTrendKg {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(String(format: "%+.1f", unit.fromKg(ch) - unit.fromKg(0))) \(unit.rawValue)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("trend weight").foregroundStyle(theme.muted)
                }
                var line = "\(fmt(unit.fromKg(a))) → \(fmt(unit.fromKg(b))) \(unit.rawValue)"
                let _ = { if let t = info.targetWeightKg {
                    let left = unit.fromKg(b) - unit.fromKg(t)
                    line += abs(left) < 0.05 ? " · at the \(fmt(unit.fromKg(t))) target"
                        : " · \(fmt(abs(left))) \(unit.rawValue) \(left > 0 ? "above" : "below") the \(fmt(unit.fromKg(t))) target"
                } }()
                Text(line).font(.footnote).foregroundStyle(theme.muted)
                chart
                HStack(alignment: .top, spacing: 10) {
                    metric(report.avgWeeklyChangeKg.map { "\(String(format: "%+.2f", unit.fromKg($0) - unit.fromKg(0))) \(unit.rawValue)" } ?? "—", "Average a week")
                    metric(report.fastestWeekKg.map { "\(String(format: "%+.1f", unit.fromKg($0) - unit.fromKg(0))) \(unit.rawValue)" } ?? "—", "Fastest week")
                    metric("\(report.daysWeighed) of \(report.days)", "Days weighed")
                }
            } else {
                Text("No weigh-ins in this campaign.").foregroundStyle(theme.muted)
            }
        }
    }

    private var chart: some View {
        let end = min(info.end ?? today, today)
        let pts = trend.filter { $0.date >= info.start && $0.date <= end }
        return Chart {
            ForEach(pts) { p in
                LineMark(x: .value("Date", p.date), y: .value("Trend", unit.fromKg(p.trendKg)))
                    .foregroundStyle(theme.accent).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            if let f = pts.first { PointMark(x: .value("Date", f.date), y: .value("Trend", unit.fromKg(f.trendKg))).foregroundStyle(theme.accent) }
            if let l = pts.last { PointMark(x: .value("Date", l.date), y: .value("Trend", unit.fromKg(l.trendKg))).foregroundStyle(theme.accent) }
            if let t = info.targetWeightKg {
                RuleMark(y: .value("Target", unit.fromKg(t))).foregroundStyle(theme.good)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .bottom, alignment: .leading) {
                        Text("target \(fmt(unit.fromKg(t)))").font(.caption2).foregroundStyle(theme.good)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 140)
    }

    // MARK: compliance

    private var complianceCard: some View {
        let c = report.compliance
        return Card(title: "Compliance") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int((c.rate * 100).rounded()))%").font(.system(size: 38, weight: .bold, design: .rounded))
                Text("\(c.compliedDays) of \(c.windowDays) days complied").foregroundStyle(theme.muted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 17), spacing: 3)], spacing: 3) {
                ForEach(Array(report.strip.enumerated()), id: \.offset) { _, d in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(d == .complied ? theme.good : (d == .missed ? theme.bad : theme.track))
                        .frame(height: 14)
                }
            }
            .accessibilityLabel("\(c.compliedDays) of \(c.windowDays) days complied")
            Text("One square per day, oldest first. Green complied, red not, grey still open.").font(.caption2).foregroundStyle(theme.muted)
            ForEach(Tracker.allCases) { t in
                HStack {
                    Text(t.title).frame(width: 80, alignment: .leading).font(.subheadline)
                    ProgressView(value: c.rate(for: t))
                    Text("\(c.perTracker[t, default: 0])/\(c.windowDays)").font(.caption).monospacedDigit()
                        .foregroundStyle(theme.muted).frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    // MARK: goals

    private var goalsCard: some View {
        let g = report.goalsAtEnd
        let a = report.averages
        return Card(title: "Goals") {
            if report.dailyGoalDays == 0 && report.weeklyGoals == 0 && g == nil {
                Text("No goals were set in this campaign.").foregroundStyle(theme.muted)
            } else {
                if report.dailyGoalDays > 0 { line("Daily goals met", "\(report.dailyGoalDaysMet) of \(report.dailyGoalDays) days") }
                if report.weeklyGoals > 0 { line("Weekly goals met", "\(report.weeklyGoalsMet) of \(report.weeklyGoals) finished weeks") }
                if let g {
                    Divider()
                    if let c = g.caloriesWeekly { line("Calories, average a day", "\(whole(a.calories)) of \((Double(c) / 7).rounded().formatted()) goal") }
                    if let p = g.proteinDaily { line("Protein, average", "\(whole(a.proteinG)) g of \(p) g goal") }
                    if let s = g.stepsDaily { line(g.stepsIsWeeklyAverage ? "Steps, weekly average" : "Steps, average a day", "\(whole(a.steps)) of \(s.formatted()) goal") }
                    if let w = g.waterDailyMl { line("Water, average a day", "\(whole(a.waterMl)) of \(w.formatted()) ml goal") }
                    if let n = g.workoutDaysWeekly { line("Workout days, average a week", "\(report.workoutsPerWeek.map { fmt($0) } ?? "—") of \(n) target") }
                }
            }
        }
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(k); Spacer(); Text(v).foregroundStyle(theme.muted).multilineTextAlignment(.trailing) }
            .font(.subheadline)
    }

    // MARK: averages

    private var averagesCard: some View {
        let a = report.averages
        return Card(title: "Averages") {
            HStack(alignment: .top, spacing: 10) {
                metric(whole(a.calories), "Calories")
                metric(a.proteinG.map { "\(whole($0)) g" } ?? "—", "Protein")
                metric(whole(a.steps), "Steps")
            }
            HStack(alignment: .top, spacing: 10) {
                metric(a.carbsG.map { "\(whole($0)) g" } ?? "—", "Carbs")
                metric(a.fatG.map { "\(whole($0)) g" } ?? "—", "Fat")
                metric(a.waterMl.map { "\(whole($0)) ml" } ?? "—", "Water")
            }
            Divider()
            Text("Biofeedback, average of 5").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(Rating.allCases) { r in
                    if let v = report.ratingAverages[r.rawValue] {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(r.title) \(fmt(v))").font(.caption.weight(.semibold))
                            Text(r.betterNote).font(.caption2).foregroundStyle(theme.muted)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.muted.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    // MARK: actions

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Label") {
                TextField(info.title, text: $labelText)
                    .multilineTextAlignment(.trailing).submitLabel(.done)
                    .onSubmit { saveLabel() }
            }
            if report.started {
                Divider()
                Button {
                    saveLabel()
                    filterRaw = info.id.uuidString
                    nav.tab = 0
                } label: {
                    HStack {
                        Label("Open on Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.muted)
                    }
                    .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                Text("Switches to the Dashboard tab with this campaign selected, to see its charts.")
                    .font(.caption).foregroundStyle(theme.muted)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.border, lineWidth: 1))
    }

    private func metric(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.caption2).foregroundStyle(theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveLabel() {
        guard let m = allCampaigns.first(where: { $0.id == info.id }),
              CampaignRules.cleanLabel(labelText) != CampaignRules.cleanLabel(m.label) else { return }
        CampaignStore.rename(context, m, to: labelText)
    }
}

// MARK: - New campaign

struct NewCampaignForm: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    let minStart: Date

    @State private var label = ""
    @State private var kind: CampaignKind = .cut
    @State private var target = ""
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var weeks = 8
    @State private var error: String?

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label (optional), e.g. Summer cut", text: $label)
                        .textInputAutocapitalization(.sentences)
                    Picker("Type", selection: $kind) {
                        ForEach(CampaignKind.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
                .listRowBackground(theme.card)

                Section {
                    LabeledContent("Target weight (\(unit.rawValue))") {
                        TextField(kind == .maintenance ? "optional" : "e.g. 70", text: $target)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    DatePicker("Start date", selection: $start, in: minStart...farthest, displayedComponents: .date)
                    Stepper("Length: \(weeks) week\(weeks == 1 ? "" : "s")", value: $weeks, in: 1...104)
                } footer: {
                    Text((start > today ? "Starts in the future: until then the current campaign carries on. " : "")
                         + "The label is shown with the dates, which follow the start and length (\(CampaignRules.cleanLabel(label) ?? "Campaign") · \(periodPreview)). "
                         + "Ends \(plannedEnd.formatted(date: .abbreviated, time: .omitted)). You can end it early at any time; it stays in your history.")
                }
                .listRowBackground(theme.card)

                if let error { Text(error).foregroundStyle(theme.bad).listRowBackground(theme.card) }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("New campaign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Start") { save() } }
            }
        }
    }

    /// What the dates will read like, for the footer.
    private var periodPreview: String {
        CampaignRules.periodText(CampaignInfo(number: 0, kind: kind, start: Calendar.current.startOfDay(for: start), plannedWeeks: weeks))
    }

    /// Campaigns can be planned up to a year ahead.
    private var farthest: Date { Calendar.current.date(byAdding: .day, value: 365, to: today)! }

    private var plannedEnd: Date {
        Calendar.current.date(byAdding: .day, value: weeks * 7 - 1, to: Calendar.current.startOfDay(for: start))!
    }

    private func save() {
        let raw = target.replacingOccurrences(of: ",", with: ".")
        let kg = Double(raw).map(unit.toKg)
        if !target.isEmpty && kg == nil { error = "Enter the target weight as a number."; return }
        switch CampaignStore.start(context, kind: kind, targetKg: kg, start: start, weeks: weeks, label: label) {
        case .success: dismiss()
        case .failure(.campaignRunning): error = "A campaign is already running. End it first."
        case .failure(.startsBeforeCurrent): error = "The start date can't be before the current campaign began."
        case .failure(.invalidWeeks): error = "Length must be at least 1 week."
        }
    }
}

#if DEBUG
/// Debug aid for screenshots: `-debugScreen campaigndetail -campaignNumber 2` opens that campaign's look back.
struct DebugCampaignDetail: View {
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @AppStorage(SettingsKey.required) private var requiredRaw = RequiredTrackers.defaultRaw
    @Query(sort: \Campaign.number) private var campaigns: [Campaign]
    @Query(sort: \DayLog.day) private var logs: [DayLog]
    @Query private var weekGoals: [WeekGoal]

    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let infos = campaigns.map(\.info)
        let snaps = logs.map(\.snapshot)
        let trend = Metrics.weightTrend(snaps, through: today, smoothingDays: smoothing)
        let n = UserDefaults.standard.integer(forKey: "campaignNumber")
        if let c = infos.first(where: { $0.number == n }) ?? infos.first {
            NavigationStack {
                CampaignDetail(info: c, report: Insights.campaignReport(c, snaps: snaps, trend: trend,
                               timeline: GoalTimeline(weekGoals, campaigns: infos), required: RequiredTrackers.parse(requiredRaw), today: today),
                               trend: trend)
            }
        }
    }
}
#endif
