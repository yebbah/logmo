import SwiftUI
import SwiftData

/// Set one campaign's goals for one Monday-to-Sunday week. Only this week and the next four (inside the
/// campaign) can be changed; earlier weeks are locked, because changing one would change its result and
/// your streaks.
struct GoalsEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var goals: [WeekGoal]

    let campaign: CampaignInfo
    @State private var weekStart: Date
    @State private var calories = ""                // per day, on average
    @State private var loadedWeekly: Int?           // the stored weekly total, kept if the field isn't touched
    @State private var protein = ""
    @State private var steps = ""
    @State private var stepsAverage = false
    @State private var workouts = ""
    @State private var water = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var pendingPrefill: GoalSet?        // a suggestion to start from ("Edit first")
    @State private var atOrUnder = true
    @State private var repeatOn = false
    @State private var repeatCount = 1

    init(campaign: CampaignInfo, week: Date? = nil, prefill: GoalSet? = nil) {
        self.campaign = campaign
        _pendingPrefill = State(initialValue: prefill)
        _weekStart = State(initialValue: GoalsEditor.initialWeek(campaign, requested: week))
    }

    /// The week asked for, else next week on a Sunday (the day plans are made), else this week; kept editable.
    static func initialWeek(_ c: CampaignInfo, requested: Date?, today: Date = Date()) -> Date {
        let cal = Calendar.current
        let b = PlanRules.bounds(c, today: today)
        guard let e = b.editable else { return b.last }
        let thisWeek = Metrics.weekStart(of: today)
        let wanted = requested ?? (cal.component(.weekday, from: today) == 1 ? cal.date(byAdding: .day, value: 7, to: thisWeek)! : thisWeek)
        return min(max(wanted, e.lowerBound), e.upperBound)
    }

    private var cal: Calendar { .current }
    private var today: Date { Date() }
    private var bounds: PlanBounds { PlanRules.bounds(campaign, today: today) }
    private var campaignWeeks: [Date: GoalSet] {
        Dictionary(goals.filter { $0.campaignID == campaign.id }.map { ($0.weekStart, $0.goalSet) }, uniquingKeysWith: { a, _ in a })
    }
    private var explicit: Set<Date> { PlanStore.explicitWeeks(goals, campaignID: campaign.id) }
    private var previous: GoalSet? { PlanRules.effective(campaignWeeks, at: cal.date(byAdding: .day, value: -7, to: weekStart)!) }
    private var followingAvailable: Int { PlanRules.followingWeeks(after: weekStart, bounds: bounds) }

    private var weekLabel: String {
        let end = cal.date(byAdding: .day, value: 6, to: weekStart)!
        let f = Date.FormatStyle().day().month(.abbreviated)
        let thisWeek = Metrics.weekStart(of: today)
        let tag = weekStart == thisWeek ? " · this week" : weekStart == cal.date(byAdding: .day, value: 7, to: thisWeek)! ? " · next week" : ""
        return "\(weekStart.formatted(f)) – \(end.formatted(f))\(tag)"
    }

    var body: some View {
        Form {
            if bounds.editable == nil {
                Section { Text("This campaign has ended, so its weeks are locked.").foregroundStyle(theme.muted) }
                    .listRowBackground(theme.card)
            } else {
                editor
            }
        }
        .scrollContentBackground(.hidden)
        .keyboardDismissible()
        .background(theme.bg)
        .navigationTitle("Set a week")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
        .onChange(of: weekStart) { _, _ in load(); repeatCount = min(repeatCount, max(followingAvailable, 1)) }
    }

    @ViewBuilder private var editor: some View {
        let e = bounds.editable!
        Section {
            Text(CampaignRules.titleWithPeriod(campaign)).font(.footnote).foregroundStyle(theme.muted)
            HStack {
                Button { move(-7) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).disabled(weekStart <= e.lowerBound)
                Spacer()
                Text(weekLabel).font(.headline)
                Spacer()
                Button { move(7) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless).disabled(weekStart >= e.upperBound)
            }
            if !explicit.contains(weekStart) {
                Text(campaignWeeks.isEmpty ? "No goals yet for this campaign."
                     : "Not set yet: showing the goals carried over from the week before.")
                    .font(.caption).foregroundStyle(theme.muted)
            }
        }
        .listRowBackground(theme.card)

        Section {
            HStack(spacing: 10) {
                startButton("Last week", enabled: previous != nil) { fill(previous) }
                startButton("Blank", enabled: true) { fill(GoalSet()) }
            }
        } header: { Text("Start from") } footer: {
            Text("Every field starts from last week, so you only change what's different.")
        }
        .listRowBackground(theme.card)

        Section {
            row("Calories per day (kcal)", $calories, was: wasCalories)
            Picker("Goal is to stay", selection: $atOrUnder) {
                Text("At or under").tag(true)
                Text("At or over").tag(false)
            }
        } header: { Text("Calories") } footer: {
            Text("Enter your daily goal, for example 1,800. It is judged on the week's average, so you can cycle: more on some days and less on others, as long as the week averages out (1,800 a day is 12,600 for the week). A finished week needs calories logged on all seven days to count as met.")
        }
        .listRowBackground(theme.card)

        Section {
            row("Workout days per week", $workouts, was: wasText(previous?.workoutDaysWeekly, workouts))
        } header: { Text("Training") } footer: {
            Text("A workout day is a day with a Training performance rating (1–5). Mark a rest day \"n/a\" on the Log screen and it isn't counted. Judged per week; 0 to 7.")
        }
        .listRowBackground(theme.card)

        Section {
            row("Protein (g)", $protein, was: wasText(previous?.proteinDaily, protein))
            row("Water (ml)", $water, was: wasText(previous?.waterDailyMl, water))
        } header: { Text("Every day") } footer: {
            Text("Each is met at or above the goal. A day with no value logged is not met.")
        }
        .listRowBackground(theme.card)

        Section {
            row("Steps per day", $steps, was: wasText(previous?.stepsDaily, steps))
            Picker("Judged as", selection: $stepsAverage) {
                Text("Daily total").tag(false)
                Text("Weekly average").tag(true)
            }
        } header: { Text("Steps") } footer: {
            Text(stepsAverage
                 ? "The week's average daily steps must reach the goal. One low day is fine if the others make up for it. A finished week needs steps logged on all seven days."
                 : "Every day's total must reach the goal. A day with no steps logged is not met.")
        }
        .listRowBackground(theme.card)

        Section {
            row("Carbs (g)", $carbs, was: wasText(previous?.carbsDaily, carbs))
            row("Fat (g)", $fat, was: wasText(previous?.fatDaily, fat))
        } header: { Text("Guidance") } footer: {
            Text("A guide for what to eat. It shows as a hint on the Log screen and is never judged as met or missed.")
        }
        .listRowBackground(theme.card)

        if followingAvailable > 0 {
            Section {
                Toggle("Repeat for the weeks after", isOn: $repeatOn)
                if repeatOn {
                    Stepper("Following weeks: \(repeatCount)", value: $repeatCount, in: 1...followingAvailable)
                }
            } footer: {
                Text("Gives the following weeks these goals, up to four weeks ahead and inside the campaign. Weeks you already set yourself are not overwritten, and each can still be edited.")
            }
            .listRowBackground(theme.card)
        }

        Section {
            Button("Save goals for this week") { save() }.frame(maxWidth: .infinity).fontWeight(.semibold)
        }
        .listRowBackground(theme.card)
    }

    // MARK: pieces

    private func startButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                .foregroundStyle(enabled ? theme.accent : theme.muted)
                .background(theme.track, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless).disabled(!enabled)
    }

    private func row(_ title: String, _ text: Binding<String>, was: String?) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if let was { Text(was).font(.caption2).foregroundStyle(theme.muted) }
                TextField("none", text: text).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    .foregroundStyle(was == nil ? Color.primary : theme.accent)
            }
        }
    }

    /// "was 2,100" when the field differs from last week's value, nil when it is the same.
    private func wasText(_ prev: Int?, _ now: String) -> String? {
        guard let prev else { return nil }
        return Int(now) == prev ? nil : "was \(prev.formatted())"
    }
    private var wasCalories: String? {
        guard let w = previous?.caloriesWeekly else { return nil }
        let perDay = Int((Double(w) / 7).rounded())
        return Int(calories) == perDay ? nil : "was \(perDay.formatted())"
    }

    private func move(_ days: Int) {
        guard let e = bounds.editable, let n = cal.date(byAdding: .day, value: days, to: weekStart), e.contains(n) else { return }
        weekStart = n
    }

    private func fill(_ g: GoalSet?) {
        let g = g ?? GoalSet()
        loadedWeekly = g.caloriesWeekly
        calories = g.caloriesWeekly.map { String(Int((Double($0) / 7).rounded())) } ?? ""
        protein = g.proteinDaily.map(String.init) ?? ""
        steps = g.stepsDaily.map(String.init) ?? ""
        stepsAverage = g.stepsIsWeeklyAverage
        workouts = g.workoutDaysWeekly.map(String.init) ?? ""
        water = g.waterDailyMl.map(String.init) ?? ""
        carbs = g.carbsDaily.map(String.init) ?? ""
        fat = g.fatDaily.map(String.init) ?? ""
        atOrUnder = g.caloriesAtOrUnder
    }

    private func load() {
        if let p = pendingPrefill { pendingPrefill = nil; fill(p); return }       // the first load shows the suggestion
        fill(PlanRules.effective(campaignWeeks, at: weekStart))
    }

    private func currentGoals() -> GoalSet {
        // Entered per day; stored as the weekly total. An untouched field keeps the stored total, so an
        // older goal (for example 14,500 a week) isn't rounded to 14,497 by re-saving.
        var weekly: Int?
        if let perDay = Int(calories) {
            let untouched = loadedWeekly.map { String(Int((Double($0) / 7).rounded())) == calories } ?? false
            weekly = untouched ? loadedWeekly : perDay * 7
        }
        return GoalSet(caloriesWeekly: weekly, caloriesAtOrUnder: atOrUnder, proteinDaily: Int(protein),
                       stepsDaily: Int(steps), stepsIsWeeklyAverage: stepsAverage, waterDailyMl: Int(water),
                       workoutDaysWeekly: Int(workouts).map { min(max($0, 0), 7) },
                       carbsDaily: Int(carbs), fatDaily: Int(fat))
    }

    private func save() {
        let g = currentGoals()
        PlanStore.save(context, campaignID: campaign.id, week: weekStart, goals: g)
        if repeatOn {
            let weeks = PlanRules.weeksToFill(after: weekStart, count: repeatCount, bounds: bounds, explicit: explicit)
            PlanStore.fill(context, campaignID: campaign.id, weeks: weeks, goals: g)
        }
        dismiss()
    }
}

/// Sheet wrapper for opening the editor from elsewhere.
struct GoalsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let campaign: CampaignInfo
    var week: Date? = nil
    var prefill: GoalSet? = nil
    var body: some View {
        NavigationStack {
            GoalsEditor(campaign: campaign, week: week, prefill: prefill).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
