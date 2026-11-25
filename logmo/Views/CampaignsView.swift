import SwiftUI
import SwiftData

/// Settings → Fitness campaigns: the running campaign, how to start or end one, and the full history.
struct CampaignsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @Query(sort: \Campaign.number, order: .reverse) private var campaigns: [Campaign]
    @Query(sort: \DayLog.day) private var logs: [DayLog]

    @State private var showNew = false
    @State private var confirmEnd = false

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var infos: [CampaignInfo] { campaigns.map(\.info) }
    private var current: CampaignInfo? { CampaignRules.campaign(for: today, in: infos) }
    private var running: Campaign? { campaigns.first { !$0.isDefault && $0.end == nil } }

    var body: some View {
        let snaps = logs.map(\.snapshot)
        let trend = Metrics.weightTrend(snaps, through: today, smoothingDays: smoothing)

        Form {
            Section("Current") {
                if let c = current {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.title).font(.headline)
                        Text(statusLine(c)).font(.caption).foregroundStyle(theme.muted)
                    }
                } else {
                    Text("No campaign yet.").foregroundStyle(theme.muted)
                }
                if let r = running {
                    Button("End this campaign now", role: .destructive) { confirmEnd = true }
                        .confirmationDialog("End campaign \(r.number) today?", isPresented: $confirmEnd, titleVisibility: .visible) {
                            Button("End campaign", role: .destructive) { CampaignStore.end(context, r) }
                        } message: {
                            Text("It stays in your history. A default maintenance campaign starts tomorrow.")
                        }
                } else {
                    Button("Start a campaign") { showNew = true }
                }
            }
            .listRowBackground(theme.card)

            Section {
                if campaigns.isEmpty {
                    Text("Campaigns appear here once you log something.").foregroundStyle(theme.muted)
                }
                ForEach(campaigns) { m in
                    NavigationLink {
                        CampaignDetail(info: m.info, snaps: snaps, trend: trend)
                    } label: {
                        row(m.info, Insights.campaignSummary(m.info, snaps: snaps, trend: trend, today: today))
                    }
                }
            } header: { Text("History") } footer: {
                Text("Every day belongs to one campaign. Between campaigns, a default maintenance campaign keeps that stretch's history, numbered after the last one.")
            }
            .listRowBackground(theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle("Fitness campaigns")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { CampaignStore.ensureDefault(context) }
        .sheet(isPresented: $showNew) { NewCampaignForm(minStart: openDefaultStart) }
    }

    private var openDefaultStart: Date {
        campaigns.first { $0.isDefault && $0.end == nil }?.start ?? today
    }

    private func statusLine(_ c: CampaignInfo) -> String {
        let df = Date.FormatStyle().day().month(.abbreviated)
        if c.isDefault { return "Maintenance since \(c.start.formatted(df)). Start a campaign any time." }
        var parts = ["\(c.plannedWeeks ?? 0) weeks from \(c.start.formatted(df))"]
        if let left = CampaignRules.daysLeft(c, today: today), c.end == nil { parts.append("\(left) \(left == 1 ? "day" : "days") left") }
        if let t = c.targetWeightKg { parts.append("target \(String(format: "%.1f", unit.fromKg(t))) \(unit.rawValue)") }
        return parts.joined(separator: " · ")
    }

    private func row(_ c: CampaignInfo, _ s: CampaignSummary) -> some View {
        let df = Date.FormatStyle().day().month(.abbreviated)
        let range = c.end.map { "\(c.start.formatted(df)) – \($0.formatted(df))" } ?? "since \(c.start.formatted(df))"
        let status = c.end == nil ? "running" : (c.endedEarly ? "ended early" : (c.isDefault ? "closed" : "completed"))
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(c.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(status).font(.caption).foregroundStyle(theme.muted)
            }
            Text(range).font(.caption).foregroundStyle(theme.muted)
            if let ch = s.changeKg {
                Text("Trend \(String(format: "%+.2f", unit.fromKg(ch) - unit.fromKg(0))) \(unit.rawValue)")
                    .font(.caption).foregroundStyle(theme.muted)
            }
        }
    }
}

// MARK: - Detail

struct CampaignDetail: View {
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage("campaignFilter") private var filterRaw = "current"
    let info: CampaignInfo
    let snaps: [DaySnapshot]
    let trend: [TrendPoint]

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        let s = Insights.campaignSummary(info, snaps: snaps, trend: trend, today: today)
        let df = Date.FormatStyle().day().month(.abbreviated).year()
        Form {
            Section("Campaign") {
                line("Type", info.kind.title + (info.isDefault ? " (default)" : ""))
                line("Started", info.start.formatted(df))
                if let e = info.end { line("Ended", e.formatted(df) + (info.endedEarly ? " (early)" : "")) } else { line("Status", "Running") }
                if let w = info.plannedWeeks {
                    line("Planned length", "\(w) weeks")
                    if let pe = CampaignRules.plannedEnd(info) { line("Planned end", pe.formatted(df)) }
                }
                if let t = info.targetWeightKg { line("Target weight", "\(String(format: "%.1f", unit.fromKg(t))) \(unit.rawValue)") }
            }
            .listRowBackground(theme.card)

            Section("Results") {
                line("Length so far", "\(s.days) day\(s.days == 1 ? "" : "s")")
                line("Days logged", "\(s.daysLogged) of \(s.days)")
                if let a = s.startTrendKg, let b = s.endTrendKg {
                    line("Trend weight", "\(String(format: "%.1f", unit.fromKg(a))) → \(String(format: "%.1f", unit.fromKg(b))) \(unit.rawValue)")
                    line("Change", "\(String(format: "%+.2f", unit.fromKg(b - a) - unit.fromKg(0))) \(unit.rawValue)")
                    if let t = info.targetWeightKg {
                        let left = unit.fromKg(b) - unit.fromKg(t)
                        line("Versus target", abs(left) < 0.05 ? "Reached" : String(format: "%.1f %@ %@", abs(left), unit.rawValue, left > 0 ? "above" : "below"))
                    }
                } else {
                    line("Trend weight", "No weigh-ins in this campaign")
                }
                line("Average calories", s.averages.calories.map { Int($0.rounded()).formatted() } ?? "—")
                line("Average protein", s.averages.proteinG.map { "\(Int($0.rounded())) g" } ?? "—")
                line("Average steps", s.averages.steps.map { Int($0.rounded()).formatted() } ?? "—")
            }
            .listRowBackground(theme.card)

            Section {
                Button("Show on dashboard") { filterRaw = info.id.uuidString }
            } footer: { Text("Open the Dashboard tab to see this campaign's charts.") }
            .listRowBackground(theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle("Campaign \(info.number)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func line(_ k: String, _ v: String) -> some View {
        LabeledContent(k) { Text(v).foregroundStyle(theme.muted) }
    }
}

// MARK: - New campaign

struct NewCampaignForm: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    let minStart: Date

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
                    DatePicker("Start date", selection: $start, in: minStart...max(today, minStart), displayedComponents: .date)
                    Stepper("Length: \(weeks) week\(weeks == 1 ? "" : "s")", value: $weeks, in: 1...104)
                } footer: {
                    Text("Ends \(plannedEnd.formatted(date: .abbreviated, time: .omitted)). You can end it early at any time; it stays in your history.")
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

    private var plannedEnd: Date {
        Calendar.current.date(byAdding: .day, value: weeks * 7 - 1, to: Calendar.current.startOfDay(for: start))!
    }

    private func save() {
        let raw = target.replacingOccurrences(of: ",", with: ".")
        let kg = Double(raw).map(unit.toKg)
        if !target.isEmpty && kg == nil { error = "Enter the target weight as a number."; return }
        switch CampaignStore.start(context, kind: kind, targetKg: kg, start: start, weeks: weeks) {
        case .success: dismiss()
        case .failure(.campaignRunning): error = "A campaign is already running. End it first."
        case .failure(.startsBeforeCurrent): error = "The start date can't be before the current campaign began."
        case .failure(.invalidWeeks): error = "Length must be at least 1 week."
        }
    }
}
