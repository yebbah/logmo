import SwiftUI
import SwiftData

/// Set one campaign's goals for one Monday-to-Sunday week. Opens on next week when it's
/// Sunday (the day goals are set), otherwise on the current week, kept inside the campaign.
struct GoalsEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
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
    @State private var atOrUnder = true
    @State private var savedFlash = false

    init(campaign: CampaignInfo) {
        self.campaign = campaign
        _weekStart = State(initialValue: GoalsEditor.defaultWeek(for: campaign))
    }

    private static func bounds(_ c: CampaignInfo, today: Date = Date()) -> (min: Date, max: Date) {
        let cal = Calendar.current
        let minWeek = Metrics.weekStart(of: c.start)
        var maxWeek = cal.date(byAdding: .day, value: 7, to: Metrics.weekStart(of: today))!
        if let end = c.end { maxWeek = min(maxWeek, Metrics.weekStart(of: end)) }
        return (minWeek, max(minWeek, maxWeek))
    }

    static func defaultWeek(for c: CampaignInfo, today: Date = Date()) -> Date {
        let cal = Calendar.current
        let ws = Metrics.weekStart(of: today)
        let wanted = cal.component(.weekday, from: today) == 1 ? cal.date(byAdding: .day, value: 7, to: ws)! : ws   // Sunday: plan next week
        let b = bounds(c, today: today)
        return min(max(wanted, b.min), b.max)
    }

    private var cal: Calendar { .current }
    private var thisWeek: Date { Metrics.weekStart(of: Date()) }
    private var minWeek: Date { GoalsEditor.bounds(campaign).min }
    private var maxWeek: Date { GoalsEditor.bounds(campaign).max }
    private var timeline: GoalTimeline { GoalTimeline(goals, campaign: campaign) }

    private var weekLabel: String {
        let end = cal.date(byAdding: .day, value: 6, to: weekStart)!
        let f = Date.FormatStyle().day().month(.abbreviated)
        let tag = weekStart == thisWeek ? " · this week" : weekStart == cal.date(byAdding: .day, value: 7, to: thisWeek)! ? " · next week" : ""
        return "\(weekStart.formatted(f)) – \(end.formatted(f))\(tag)"
    }

    var body: some View {
        Form {
            Section {
                Text("Goals for \(CampaignRules.titleWithPeriod(campaign)). Each campaign keeps its own.")
                    .font(.footnote).foregroundStyle(theme.muted)
                HStack {
                    Button { move(-7) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless).disabled(weekStart <= minWeek)
                    Spacer()
                    Text(weekLabel).font(.headline)
                    Spacer()
                    Button { move(7) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless).disabled(weekStart >= maxWeek)
                }
                if let from = timeline.inheritedFrom(weekStart) {
                    Text("No goals set for this week. Showing goals from the week of \(from.formatted(date: .abbreviated, time: .omitted)); save to set this week's.")
                        .font(.caption).foregroundStyle(theme.muted)
                } else if timeline.byWeek.isEmpty {
                    Text("No goals yet for this campaign. Leave a field empty to have no goal for it.")
                        .font(.caption).foregroundStyle(theme.muted)
                }
            }
            .listRowBackground(theme.card)

            Section {
                row("Calories per day (kcal)", $calories)
                Picker("Goal is to stay", selection: $atOrUnder) {
                    Text("At or under").tag(true)
                    Text("At or over").tag(false)
                }
            } header: { Text("Calories") } footer: {
                Text("Enter your daily goal, for example 1,800. It is judged on the week's average, so you can cycle: more on some days and less on others, as long as the week averages out (1,800 a day is 12,600 for the week). A finished week needs calories logged on all seven days to count as met.")
            }
            .listRowBackground(theme.card)

            Section {
                row("Workout days per week", $workouts)
            } header: { Text("Training") } footer: {
                Text("A workout day is a day with a Training performance rating (1–5). Mark a rest day \"n/a\" on the Log screen and it isn't counted. Judged per week; 0 to 7.")
            }
            .listRowBackground(theme.card)

            Section {
                row("Protein (g)", $protein)
                row("Water (ml)", $water)
            } header: { Text("Every day") } footer: {
                Text("Each is met at or above the goal. A day with no value logged is not met.")
            }
            .listRowBackground(theme.card)

            Section {
                row("Steps per day", $steps)
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
                Button(savedFlash ? "Saved ✓" : "Save goals for this week") { save() }
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle("Weekly goals")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
        .onChange(of: weekStart) { _, _ in load() }
    }

    private func row(_ title: String, _ text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("none", text: text).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
        }
    }

    private func move(_ days: Int) {
        if let n = cal.date(byAdding: .day, value: days, to: weekStart), n >= minWeek, n <= maxWeek { weekStart = n }
    }

    private func load() {
        let g = timeline.goals(forWeekStarting: weekStart)
        loadedWeekly = g?.caloriesWeekly
        calories = g?.caloriesWeekly.map { String(Int((Double($0) / 7).rounded())) } ?? ""
        protein = g?.proteinDaily.map(String.init) ?? ""
        steps = g?.stepsDaily.map(String.init) ?? ""
        stepsAverage = g?.stepsIsWeeklyAverage ?? false
        workouts = g?.workoutDaysWeekly.map(String.init) ?? ""
        water = g?.waterDailyMl.map(String.init) ?? ""
        atOrUnder = g?.caloriesAtOrUnder ?? true
        savedFlash = false
    }

    private func save() {
        let goal = goals.first { $0.campaignID == campaign.id && $0.weekStart == weekStart } ?? {
            let g = WeekGoal(weekStart: weekStart, campaignID: campaign.id); context.insert(g); return g
        }()
        // Entered per day; stored as the weekly total. An untouched field keeps the stored total, so
        // an older goal (for example 14,500 a week) isn't rounded to 14,497 by re-saving.
        if let perDay = Int(calories) {
            let untouched = loadedWeekly.map { String(Int((Double($0) / 7).rounded())) == calories } ?? false
            goal.caloriesWeekly = untouched ? loadedWeekly : perDay * 7
        } else {
            goal.caloriesWeekly = nil
        }
        goal.caloriesAtOrUnder = atOrUnder
        goal.proteinDaily = Int(protein)
        goal.stepsDaily = Int(steps)
        goal.stepsIsWeeklyAverage = stepsAverage
        goal.workoutDaysWeekly = Int(workouts).map { min(max($0, 0), 7) }
        goal.waterDailyMl = Int(water)
        goal.updatedAt = Date()
        try? context.save()
        savedFlash = true
    }
}

/// Sheet wrapper for opening the editor from the dashboard.
struct GoalsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let campaign: CampaignInfo
    var body: some View {
        NavigationStack {
            GoalsEditor(campaign: campaign).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
