import SwiftUI
import SwiftData

/// "Suggest next week": shows exactly what the assistant will see, then proposes next week's goals with reasons.
/// Available any day, to assess the week so far or last week. Nothing is saved until the user taps Use.
struct SuggestSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.trackCycle) private var trackCycle = false
    @AppStorage(SettingsKey.trackSick) private var trackSick = false
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @Query(sort: \DayLog.day) private var logs: [DayLog]
    @Query private var weekGoals: [WeekGoal]
    @Query(sort: \Campaign.number) private var campaigns: [Campaign]

    let campaign: CampaignInfo
    /// "Edit first": the caller opens the normal week editor filled with these goals.
    var onEdit: (GoalSet, Date) -> Void

    enum Phase: Equatable { case preview, working, result(PlanSuggestion) }
    @State private var phase: Phase = .preview
    @State private var window: AssessedWeek = .thisWeekSoFar
    @State private var includeCycle = true
    @State private var includeSick = true
    @State private var chosenDefault = false

    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var nextWeek: Date { cal.date(byAdding: .day, value: 7, to: Metrics.weekStart(of: today))! }
    private var canPlanNextWeek: Bool { PlanRules.bounds(campaign, today: today).editable?.contains(nextWeek) == true }

    private var timeline: GoalTimeline { GoalTimeline(weekGoals, campaigns: campaigns.map(\.info)) }
    private var thisWeeksGoals: GoalSet? { timeline.goals(forDay: today) }

    private var summary: WeekSummary {
        SuggestionRules.summary(campaign: campaign, snaps: logs.map(\.snapshot), current: thisWeeksGoals, window: window,
                                includeCycle: trackCycle && includeCycle, includeSick: trackSick && includeSick, today: today,
                                smoothingDays: smoothing, seeds: CampaignRules.trendSeeds(campaigns.map(\.info)), profile: MaintenanceProfile.load())
    }

    private var nextWeekLabel: String {
        let end = cal.date(byAdding: .day, value: 6, to: nextWeek)!
        let f = Date.FormatStyle().day().month(.abbreviated)
        return "\(nextWeek.formatted(f)) – \(end.formatted(f))"
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .preview: preview
                case .working: working
                case .result(let p): result(p)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Suggest next week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                #if DEBUG
                // Debug aid for screenshots: -suggestRun 1 goes straight to the suggestion
                if UserDefaults.standard.bool(forKey: "suggestRun") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { run(summary) } }
                #endif
                guard !chosenDefault else { return }
                chosenDefault = true
                // This week so far when there is enough of it; otherwise look at last week.
                window = SuggestionRules.hasEnoughData(SuggestionRules.summary(campaign: campaign, snaps: logs.map(\.snapshot), current: thisWeeksGoals,
                            window: .thisWeekSoFar, includeCycle: false, includeSick: false, today: today,
                            smoothingDays: smoothing, seeds: CampaignRules.trendSeeds(campaigns.map(\.info)), profile: MaintenanceProfile.load())) ? .thisWeekSoFar : .lastWeek
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Preview: what is shared

    private var preview: some View {
        let s = summary
        return Form {
            Section {
                Picker("Assess", selection: $window) {
                    Text("This week so far").tag(AssessedWeek.thisWeekSoFar)
                    Text("Last week").tag(AssessedWeek.lastWeek)
                }.pickerStyle(.segmented)
                Text("For \(nextWeekLabel). \(s.daysLogged) of \(s.daysCovered) days logged in the week assessed.")
                    .font(.footnote).foregroundStyle(theme.muted)
            }
            .listRowBackground(theme.card)

            Section {
                row("Campaign", "\(s.kind.title) · week \(s.weekNumber)" + (s.totalWeeks.map { " of \($0)" } ?? ""))
                row("Weight trend", s.weightChangeKgPerWeek.map { String(format: "%+.2f kg a week", $0) } ?? "not enough weigh-ins", goal: "\(s.weighIns) weigh-ins, 21 days")
                row("Calories", "\(s.avgCalories.map { $0.formatted() } ?? "—") a day", goal: s.current.caloriesWeekly.map { "goal \(($0 / 7).formatted())" })
                if let m = s.estimatedMaintenance { row("Estimated maintenance", "\(m.formatted()) kcal a day", goal: s.maintenanceSource == .trend ? "from your logs" : "formula") }
                row("Protein, carbs, fat", "\(s.avgProteinG.map(String.init) ?? "—") / \(s.avgCarbsG.map(String.init) ?? "—") / \(s.avgFatG.map(String.init) ?? "—") g")
                row("Steps", "\(s.avgSteps.map { $0.formatted() } ?? "—") a day", goal: s.current.stepsDaily.map { "goal \($0.formatted())" })
                row("Workouts", "\(s.workoutDays)", goal: s.current.workoutDaysWeekly.map { "goal \($0)" })
                row("Days with daily goals met", "\(s.dailyGoalDaysMet) of \(s.daysCovered)")
                row("Logged on", "calories \(s.calorieDays) · steps \(s.stepsDays) · check-in \(s.ratingDays) of \(s.daysCovered) days")
                row("Check-in averages", ratingsText(s))
                if let hr = s.avgRestingHR { row("Resting heart rate", "\(hr) bpm", goal: s.restingHRChange.map { String(format: "%+.0f on the week before", $0) }) }
                if let h = s.avgHRV { row("Heart rate variability", "\(h) ms", goal: s.hrvChangePercent.map { String(format: "%+.0f%% on the week before", $0) }) }
                if let m = s.avgSleepMinutes { row("Sleep recorded", String(format: "%.1f h", Double(m) / 60), goal: "\(s.sleepNights) nights") }
                if trackCycle {
                    Toggle(isOn: $includeCycle) { VStack(alignment: .leading) { Text("Include cycle"); Text("\(s.periodDays ?? 0) period days").font(.caption).foregroundStyle(theme.muted) } }
                }
                if trackSick {
                    Toggle(isOn: $includeSick) { VStack(alignment: .leading) { Text("Include sickness"); Text("\(s.sickDays ?? 0) sick days").font(.caption).foregroundStyle(theme.muted) } }
                }
            } header: { Text("What the assistant sees") } footer: {
                Text("Numbers only: no name, email, campaign label, dates or notes. Apple Intelligence runs on your iPhone, so none of this leaves it.")
            }
            .listRowBackground(theme.card)

            Section {
                if !canPlanNextWeek {
                    Text("Next week is outside this campaign, so there is nothing to plan.").foregroundStyle(theme.muted)
                } else if !SuggestionRules.hasEnoughData(s) {
                    Text("Nothing is logged in the week assessed yet. Log a few days first.").foregroundStyle(theme.muted)
                } else {
                    Button { run(s) } label: { Text("Suggest next week").fontWeight(.semibold).frame(maxWidth: .infinity) }
                }
                if case .unavailable(let why) = AIAdvisor.availability {
                    Text("\(why) A basic, rule-based suggestion will be used.").font(.caption).foregroundStyle(theme.muted)
                }
            }
            .listRowBackground(theme.card)
        }
    }

    private func row(_ title: String, _ value: String, goal: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
            Spacer()
            if let goal { Text(goal).font(.caption).foregroundStyle(theme.muted) }
            Text(value).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }

    private func ratingsText(_ s: WeekSummary) -> String {
        let parts = Rating.allCases.compactMap { r in s.ratingAverages[r.rawValue].map { "\(r.rawValue) \(String(format: "%.1f", $0))" } }
        return parts.isEmpty ? "none logged" : parts.joined(separator: " · ")
    }

    // MARK: Working

    private var working: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Thinking about your week…").foregroundStyle(theme.muted)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func run(_ s: WeekSummary) {
        phase = .working
        Task {
            let basic = SuggestionRules.baseline(s)
            let result = await AIAdvisor.suggest(s, baseline: basic) ?? basic
            phase = .result(result)
        }
    }

    // MARK: Result

    private func result(_ p: PlanSuggestion) -> some View {
        let cur = thisWeeksGoals ?? GoalSet()
        let curCal = cur.caloriesWeekly.map { Int((Double($0) / 7).rounded()) }
        return Form {
            Section {
                goalRow("Calories", p.caloriesPerDay.formatted() + " kcal/day", was: curCal.map { $0.formatted() }, changed: curCal != p.caloriesPerDay)
                goalRow("Protein", "\(p.proteinG) g", was: cur.proteinDaily.map(String.init), changed: cur.proteinDaily != p.proteinG)
                goalRow("Carbs", "\(p.carbsG) g", was: cur.carbsDaily.map(String.init), changed: cur.carbsDaily != p.carbsG)
                goalRow("Fat", "\(p.fatG) g", was: cur.fatDaily.map(String.init), changed: cur.fatDaily != p.fatG)
                goalRow("Steps", "\(p.steps.formatted()) / day", was: cur.stepsDaily.map { $0.formatted() }, changed: cur.stepsDaily != p.steps)
                goalRow("Lifting days", "\(p.workoutDays)", was: cur.workoutDaysWeekly.map(String.init), changed: cur.workoutDaysWeekly != p.workoutDays)
                if let w = p.waterMl { goalRow("Water", "\(w.formatted()) ml", was: cur.waterDailyMl.map { $0.formatted() }, changed: cur.waterDailyMl != w) }
            } header: { Text("Suggested for \(nextWeekLabel)") } footer: {
                Text("Carbs and fat are guidance: shown in the plan and as hints on the Log screen, never judged. Nothing is saved until you tap Use.")
            }
            .listRowBackground(theme.card)

            Section {
                Text(p.headline).font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Image(systemName: confidenceIcon(p.confidence)).foregroundStyle(confidenceColor(p.confidence))
                    Text("\(p.confidence.title) confidence").font(.subheadline.weight(.semibold))
                    Spacer()
                }
                Text("Weight trend \(p.metricConfidence.weight.title.lowercased()) · calorie logs \(p.metricConfidence.nutrition.title.lowercased()) · steps \(p.metricConfidence.activity.title.lowercased()) · check-ins \(p.metricConfidence.recovery.title.lowercased())")
                    .font(.caption).foregroundStyle(theme.muted)
                if let note = p.note {
                    Label { Text(note).font(.subheadline) } icon: { Image(systemName: "sparkles").foregroundStyle(theme.accent) }
                }
            } header: { Text("In short") } footer: {
                Text(p.source == .appleIntelligence
                     ? "The numbers and evidence are calculated by logmo. Apple Intelligence on your iPhone chose within the limits and wrote the note."
                     : "A rule-based suggestion calculated by logmo on your iPhone.")
            }
            .listRowBackground(theme.card)

            Section {
                ForEach(Array(p.evidence.enumerated()), id: \.offset) { _, r in
                    Label { Text(r).font(.subheadline) } icon: { Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(theme.muted) }
                }
            } header: { Text("What the data says") } footer: {
                Text("Every figure here is calculated from what you logged. Days you didn't log are never counted as zero.")
            }
            .listRowBackground(theme.card)

            if !p.cautions.isEmpty {
                Section {
                    ForEach(Array(p.cautions.enumerated()), id: \.offset) { _, r in
                        Label { Text(r).font(.subheadline) } icon: { Image(systemName: "exclamationmark.circle").foregroundStyle(theme.warn) }
                    }
                } header: { Text("Worth knowing") }
                .listRowBackground(theme.card)
            }

            if !p.needMoreData.isEmpty {
                Section {
                    ForEach(Array(p.needMoreData.enumerated()), id: \.offset) { _, r in
                        Label { Text(r).font(.subheadline) } icon: { Image(systemName: "plus.circle").foregroundStyle(theme.accent) }
                    }
                } header: { Text("To firm this up") } footer: {
                    Text("Held to limits: a change needs a reliable trend and calorie logs, calories never go below 1,200 or lower when a target is already low, and steps and lifting days are never raised automatically. A suggestion, not medical advice.")
                }
                .listRowBackground(theme.card)
            }

            Section {
                Button { use(p) } label: { Text("Use for next week").fontWeight(.semibold).frame(maxWidth: .infinity) }
                Button("Edit first") {
                    let goals = p.goalSet(keeping: thisWeeksGoals ?? GoalSet())
                    let week = nextWeek
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onEdit(goals, week) }
                }
                Button("Not now", role: .cancel) { dismiss() }
            }
            .listRowBackground(theme.card)
        }
    }

    private func confidenceIcon(_ c: DataConfidence) -> String { c == .high ? "checkmark.seal.fill" : (c == .medium ? "checkmark.seal" : "questionmark.circle") }
    private func confidenceColor(_ c: DataConfidence) -> Color { c == .high ? theme.good : (c == .medium ? theme.accent : theme.warn) }

    private func goalRow(_ title: String, _ value: String, was: String?, changed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
            Spacer()
            if changed, let was { Text("(was \(was))").font(.caption).foregroundStyle(theme.muted) }
            Text(value).font(.headline).foregroundStyle(changed ? theme.accent : Color.primary)
        }
    }

    private func use(_ p: PlanSuggestion) {
        PlanStore.save(context, campaignID: campaign.id, week: nextWeek, goals: p.goalSet(keeping: thisWeeksGoals ?? GoalSet()))
        dismiss()
    }
}
