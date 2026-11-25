import SwiftUI
import SwiftData

/// Set goals for one Monday-to-Sunday week. Opens on next week when it's Sunday
/// (the day goals are set), otherwise on the current week.
struct GoalsEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Query private var goals: [WeekGoal]

    @State private var weekStart = GoalsEditor.defaultWeek()
    @State private var calories = ""
    @State private var protein = ""
    @State private var steps = ""
    @State private var water = ""
    @State private var atOrUnder = true
    @State private var savedFlash = false

    static func defaultWeek(today: Date = Date()) -> Date {
        let cal = Calendar.current
        let ws = Metrics.weekStart(of: today)
        // On Sunday, plan the coming week.
        return cal.component(.weekday, from: today) == 1 ? cal.date(byAdding: .day, value: 7, to: ws)! : ws
    }

    private var cal: Calendar { .current }
    private var thisWeek: Date { Metrics.weekStart(of: Date()) }
    private var maxWeek: Date { cal.date(byAdding: .day, value: 7, to: thisWeek)! }
    private var timeline: GoalTimeline { GoalTimeline(goals) }

    private var weekLabel: String {
        let end = cal.date(byAdding: .day, value: 6, to: weekStart)!
        let f = Date.FormatStyle().day().month(.abbreviated)
        let tag = weekStart == thisWeek ? " · this week" : weekStart == maxWeek ? " · next week" : ""
        return "\(weekStart.formatted(f)) – \(end.formatted(f))\(tag)"
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Button { move(-7) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
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
                    Text("No goals yet. Leave a field empty to have no goal for it.")
                        .font(.caption).foregroundStyle(theme.muted)
                }
            }
            .listRowBackground(theme.card)

            Section {
                row("Weekly total (kcal)", $calories)
                Picker("Goal is to stay", selection: $atOrUnder) {
                    Text("At or under").tag(true)
                    Text("At or over").tag(false)
                }
            } header: { Text("Weekly") } footer: {
                Text("Enter the weekly total. It is judged on the week's average: average daily calories at or under (or over) the total ÷ 7. A finished week needs calories logged on all seven days to count as met.")
            }
            .listRowBackground(theme.card)

            Section {
                row("Protein (g)", $protein)
                row("Steps", $steps)
                row("Water (ml)", $water)
            } header: { Text("Every day") } footer: {
                Text("Each is met at or above the goal. A day with no value logged is not met.")
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
        }
    }

    private func move(_ days: Int) {
        if let n = cal.date(byAdding: .day, value: days, to: weekStart), n <= maxWeek { weekStart = n }
    }

    private func load() {
        let g = timeline.goals(forWeekStarting: weekStart)
        calories = g?.caloriesWeekly.map(String.init) ?? ""
        protein = g?.proteinDaily.map(String.init) ?? ""
        steps = g?.stepsDaily.map(String.init) ?? ""
        water = g?.waterDailyMl.map(String.init) ?? ""
        atOrUnder = g?.caloriesAtOrUnder ?? true
        savedFlash = false
    }

    private func save() {
        let goal = goals.first { $0.weekStart == weekStart } ?? {
            let g = WeekGoal(weekStart: weekStart); context.insert(g); return g
        }()
        goal.caloriesWeekly = Int(calories)
        goal.caloriesAtOrUnder = atOrUnder
        goal.proteinDaily = Int(protein)
        goal.stepsDaily = Int(steps)
        goal.waterDailyMl = Int(water)
        goal.updatedAt = Date()
        try? context.save()
        savedFlash = true
    }
}

/// Sheet wrapper for opening the editor from the dashboard.
struct GoalsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            GoalsEditor().toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
