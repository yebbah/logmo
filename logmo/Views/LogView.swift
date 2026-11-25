import SwiftUI
import SwiftData

/// Editable copy of a day. Text fields stay strings so "empty" is distinguishable from 0.
struct DayDraft: Equatable {
    var weight = ""
    var calories = ""
    var protein = ""
    var fat = ""
    var carbs = ""
    var water = ""
    var steps = ""
    var ratings: [Rating: Int] = [:]
    var performanceNA = false          // training performance answered "n/a" (not a lifting day)

    var isEmpty: Bool {
        weight.isEmpty && calories.isEmpty && protein.isEmpty && fat.isEmpty && carbs.isEmpty
            && water.isEmpty && steps.isEmpty && ratings.isEmpty && !performanceNA
    }

    init() {}

    init(_ log: DayLog?, unit: WeightUnit) {
        guard let log else { return }
        if let w = log.weightKg { weight = String(format: "%.1f", unit.fromKg(w)) }
        calories = log.calories.map(String.init) ?? ""
        protein = log.proteinG.map(String.init) ?? ""
        fat = log.fatG.map(String.init) ?? ""
        carbs = log.carbsG.map(String.init) ?? ""
        water = log.waterMl.map(String.init) ?? ""
        steps = log.steps.map(String.init) ?? ""
        for r in Rating.allCases { if let v = log.rating(r) { ratings[r] = v } }
        performanceNA = log.performanceNA
    }

    func apply(to log: DayLog, unit: WeightUnit) {
        let w = Double(weight.replacingOccurrences(of: ",", with: "."))
        let newKg = w.map(unit.toKg)
        // Don't relabel an unchanged value (e.g. from Health) as manual.
        if newKg != log.weightKg {
            log.weightKg = newKg
            log.weightSource = "manual"
        }
        log.calories = Int(calories)
        log.proteinG = Int(protein)
        log.fatG = Int(fat)
        log.carbsG = Int(carbs)
        log.waterMl = Int(water)
        log.steps = Int(steps)
        for r in Rating.allCases { log.setRating(r, ratings[r]) }
        log.performanceNA = performanceNA
        log.updatedAt = Date()
    }
}

struct LogView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @Query(sort: \DayLog.day) private var logs: [DayLog]
    @Query private var weekGoals: [WeekGoal]
    @Query(sort: \Campaign.number) private var campaigns: [Campaign]

    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var draft = DayDraft()
    @State private var baseline = DayDraft()      // what is saved; autosave runs when the draft differs
    @State private var loadedDay: Date?
    @State private var showPicker = false

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    /// Goals in force for the day being edited, shown as hints in the empty fields.
    private var goals: GoalSet? {
        GoalTimeline(weekGoals, campaigns: campaigns.map(\.info)).goals(forDay: date)
    }

    /// Debug aid for screenshots: `-logSection checkin` hides the sections above the check-in.
    private var showTop: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "logSection") == nil
        #else
        return true
        #endif
    }

    /// Check-in order for the Log screen, with training performance last.
    private var checkInOrder: [Rating] {
        let all = Rating.allCases.filter { $0 != .performance } + [.performance]
        #if DEBUG
        if UserDefaults.standard.string(forKey: "logSection") == "performance" { return [.performance] }   // screenshot aid
        #endif
        return all
    }

    private func hint(_ goal: Int?) -> String { goal.map { "goal \($0.formatted())" } ?? "—" }

    private func existing(_ day: Date) -> DayLog? {
        logs.first { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    private var dateLabel: String {
        date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless)
                        Spacer()
                        Button { showPicker = true } label: {
                            Text(dateLabel).font(.headline)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(theme.track, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Date, \(dateLabel). Tap to change.")
                        Spacer()
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.borderless)
                            .disabled(date >= today)
                    }
                }
                .listRowBackground(theme.card)

                if showTop {
                    Section("Weight") {
                        field("Weight (\(unit.rawValue))", $draft.weight, "—", decimal: true)
                    }
                    .listRowBackground(theme.card)

                    Section("Food") {
                        field("Calories (kcal)", $draft.calories, "—")
                        field("Protein (g)", $draft.protein, hint(goals?.proteinDaily))
                        field("Carbs (g)", $draft.carbs, "—")
                        field("Fat (g)", $draft.fat, "—")
                    }
                    .listRowBackground(theme.card)

                    Section("Water") {
                        field("Total (ml)", $draft.water, hint(goals?.waterDailyMl))
                        HStack {
                            ForEach([250, 500, 750, 1000], id: \.self) { ml in
                                Button("+\(ml)") { addWater(ml) }
                                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .listRowBackground(theme.card)

                    Section("Activity") {
                        // The steps hint only applies when the goal is a daily total, not a weekly average.
                        field("Steps", $draft.steps, hint(goals?.dailyStepsGoal))
                    }
                    .listRowBackground(theme.card)

                }

                Section("Check-in (1–5, tap again to clear)") {
                    // Training performance comes last: it is the one that can be "not a lifting day".
                    ForEach(checkInOrder) { r in
                        RatingRow(title: r.title, low: r.low, high: r.high, value: draft.ratings[r],
                                  set: { v in
                                      draft.ratings[r] = v
                                      if r == .performance && v != nil { draft.performanceNA = false }
                                  },
                                  naAllowed: r == .performance, naOn: r == .performance && draft.performanceNA,
                                  onNA: {
                                      draft.performanceNA.toggle()
                                      if draft.performanceNA { draft.ratings[.performance] = nil }
                                  })
                    }
                }
                .listRowBackground(theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle(date == today ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Saving is automatic; this only shows where things stand.
                    Label(draft == baseline ? "Saved" : "Saving…", systemImage: draft == baseline ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                        .font(.footnote).foregroundStyle(theme.muted).labelStyle(.titleAndIcon)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .sheet(isPresented: $showPicker) { datePickerSheet }
            .onAppear { load(date) }
            .onChange(of: date) { old, new in save(day: old); load(new) }
            .onChange(of: scenePhase) { _, phase in if phase != .active { save() } }
            .onDisappear { save() }
            // Autosave: shortly after the last change, so typing isn't interrupted.
            .task(id: draft) {
                guard draft != baseline else { return }
                try? await Task.sleep(for: .milliseconds(600))
                if !Task.isCancelled { save() }
            }
        }
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("Date", selection: $date, in: ...today, displayedComponents: .date)
                .datePickerStyle(.graphical).labelsHidden().padding()
                .tint(theme.accent)
                .navigationTitle(dateLabel).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPicker = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func field(_ title: String, _ text: Binding<String>, _ placeholder: String, decimal: Bool = false) -> some View {
        LabeledContent(title) {
            TextField(placeholder, text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad).multilineTextAlignment(.trailing)
        }
    }

    private func shift(_ d: Int) {
        if let n = Calendar.current.date(byAdding: .day, value: d, to: date), n <= today { date = n }
    }

    private func addWater(_ ml: Int) {
        draft.water = String((Int(draft.water) ?? 0) + ml)
    }

    private func load(_ day: Date) {
        draft = DayDraft(existing(day), unit: unit)
        baseline = draft
        loadedDay = day
    }

    private func save(day: Date? = nil) {
        let d = Calendar.current.startOfDay(for: day ?? date)
        guard loadedDay.map({ Calendar.current.isDate($0, inSameDayAs: d) }) ?? false else { return }
        guard draft != baseline else { return }                 // nothing changed: leave stored values untouched
        if let log = existing(d) {
            if draft.isEmpty { context.delete(log) } else { draft.apply(to: log, unit: unit) }   // nothing entered = no record
        } else if !draft.isEmpty {
            let log = DayLog(day: d)
            draft.apply(to: log, unit: unit)
            context.insert(log)
        }
        try? context.save()
        baseline = draft
    }
}

struct RatingRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let low: String
    let high: String
    let value: Int?
    let set: (Int?) -> Void
    var naAllowed = false              // training performance can be answered "n/a" (not a lifting day)
    var naOn = false
    var onNA: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { n in
                        Button { set(value == n ? nil : n) } label: {
                            Text("\(n)").font(.callout.weight(.semibold))
                                .frame(width: 32, height: 32)
                                .background(value == n ? theme.accent : theme.track, in: Circle())
                                .foregroundStyle(value == n ? theme.onAccent : Color.primary)
                        }
                        .buttonStyle(.borderless)
                        .disabled(naOn)
                        .opacity(naOn ? 0.35 : 1)
                        .accessibilityLabel("\(title) \(n): \(n == 1 ? low : n == 5 ? high : "")")
                    }
                }
            }
            Text("1 = \(low) · 5 = \(high)").font(.caption).foregroundStyle(theme.muted)
            if naAllowed {
                Divider()
                Toggle(isOn: Binding(get: { naOn }, set: { _ in onNA() })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not a lifting day (n/a)")
                        Text("Rest day: not counted as a workout").font(.caption).foregroundStyle(theme.muted)
                    }
                }
            }
        }
    }
}
