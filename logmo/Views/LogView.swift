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
    var onPeriod: Bool?                // "on your period today?" nil = not answered
    var isSick: Bool?                  // "are you sick today?" nil = not answered

    var isEmpty: Bool {
        weight.isEmpty && calories.isEmpty && protein.isEmpty && fat.isEmpty && carbs.isEmpty
            && water.isEmpty && steps.isEmpty && ratings.isEmpty && !performanceNA && onPeriod == nil && isSick == nil
    }

    init() {}

    /// The text shown for a field Health can fill.
    func text(for f: HealthField) -> String {
        switch f {
        case .weight: weight
        case .calories: calories
        case .protein: protein
        case .carbs: carbs
        case .fat: fat
        case .water: water
        case .steps: steps
        case .period: onPeriod == true ? "yes" : ""
        case .sleep: ratings[.sleep].map(String.init) ?? ""
        }
    }

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
        onPeriod = log.onPeriod
        isSick = log.isSick
    }

    func apply(to log: DayLog, unit: WeightUnit) {
        let before = log.healthValues
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
        log.onPeriod = onPeriod
        log.isSick = isSick
        var imp = log.imported, over = log.overridden                       // a Health value the user changed or cleared is now theirs
        HealthMerge.markEdits(old: before, new: log.healthValues, imported: &imp, overridden: &over)
        log.imported = imp; log.overridden = over
        log.updatedAt = Date()
    }
}

struct LogView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.trackCycle) private var trackCycle = false
    @AppStorage(SettingsKey.trackSick) private var trackSick = false
    @AppStorage(SettingsKey.required) private var requiredRaw = RequiredTrackers.defaultRaw
    @AppStorage(HealthSettings.connected) private var healthConnected = false
    @State private var syncing = false
    @State private var highlightPerformance = false
    @State private var lastSyncShown: Date? = HealthSync.lastSync
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

    private var showCycle: Bool {
        #if DEBUG
        let s = UserDefaults.standard.string(forKey: "logSection")
        return s == nil || s == "cycle"
        #else
        return true
        #endif
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

    private func hint(_ goal: Int?, word: String = "goal") -> String { goal.map { "\(word) \($0.formatted())" } ?? "—" }

    private func existing(_ day: Date) -> DayLog? {
        logs.first { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    private var dateLabel: String {
        date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year())
    }

    /// Which required trackers are complete for this day, so it's clear what is still missing.
    @ViewBuilder private var completenessStrip: some View {
        let required = Tracker.allCases.filter(RequiredTrackers.parse(requiredRaw).contains)
        if !required.isEmpty {
            let done = draft.completeTrackers
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(required.allSatisfy(done.contains) ? "Everything required is logged" : "Still to log")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(required.filter(done.contains).count) of \(required.count)").font(.footnote).foregroundStyle(theme.muted)
                    }
                    HStack(spacing: 0) {
                        ForEach(required) { t in
                            let ok = done.contains(t)
                            Image(systemName: t.icon)
                                .font(.title3.weight(.semibold))
                                .frame(width: 46, height: 46)
                                .foregroundStyle(ok ? theme.good : theme.muted)
                                .background((ok ? theme.good : theme.muted).opacity(0.14), in: Circle())
                                .overlay(alignment: .bottomTrailing) {
                                    if ok {
                                        Image(systemName: "checkmark.circle.fill").font(.caption)
                                            .foregroundStyle(theme.good, theme.card)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("\(t.title), \(ok ? "done" : "not done")")
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
            .listRowBackground(theme.card)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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

                healthSections(proxy)

                completenessStrip

                if showTop {
                    Section("Weight") {
                        field("Weight (\(unit.rawValue))", $draft.weight, "—", decimal: true, health: .weight)
                        if let log = existing(date), log.healthBodyFat != nil || log.healthLeanKg != nil {
                            Label(bodyCompositionText(log), systemImage: "heart.fill")
                                .font(.caption).foregroundStyle(Color.pink).labelStyle(.titleAndIcon)
                        }
                    }
                    .listRowBackground(theme.card)

                    Section("Food") {
                        field("Calories (kcal)", $draft.calories, "—", health: .calories)
                        field("Protein (g)", $draft.protein, hint(goals?.proteinDaily), health: .protein)
                        field("Carbs (g)", $draft.carbs, hint(goals?.carbsDaily, word: "guide"), health: .carbs)
                        field("Fat (g)", $draft.fat, hint(goals?.fatDaily, word: "guide"), health: .fat)
                    }
                    .listRowBackground(theme.card)

                    Section("Water") {
                        field("Total (ml)", $draft.water, hint(goals?.waterDailyMl), health: .water)
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
                        field("Steps", $draft.steps, hint(goals?.dailyStepsGoal), health: .steps)
                    }
                    .listRowBackground(theme.card)

                }

                if showCycle && trackCycle {
                    Section("Cycle") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Are you on your period today?")
                            sourceTag(.period)
                            HStack(spacing: 10) {
                                cycleChoice("Yes", value: true)
                                cycleChoice("No", value: false)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(theme.card)
                }

                if showCycle && trackSick {
                    Section("Health") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Are you sick today?")
                            HStack(spacing: 10) {
                                yesNoChoice("Yes", value: true, current: draft.isSick, tint: theme.sick, label: "Sick today") { draft.isSick = $0 }
                                yesNoChoice("No", value: false, current: draft.isSick, tint: theme.accent, label: "Sick today") { draft.isSick = $0 }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(theme.card)
                }

                Section("Check-in (1–5, tap again to clear)") {
                    sleepHealthNote
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
                        .listRowBackground(r == .performance && highlightPerformance ? theme.accent.opacity(0.16) : theme.card)
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
            .onAppear {
                load(date); syncHealth()
                #if DEBUG
                // Debug aid for screenshots: -rateIt 1 acts as if "Rate it" had been tapped
                if UserDefaults.standard.bool(forKey: "rateIt") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if let log = existing(date) { startRating(log, proxy) } }
                }
                #endif
            }
            .onChange(of: existing(date)?.updatedAt) { _, _ in if draft == baseline { load(date) } }     // a Health update arrived while viewing
            .onChange(of: date) { old, new in save(day: old); load(new); syncHealth(force: true) }      // an older day is filled from Health too
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

    /// A yes/no choice; tapping the selected one clears the answer.
    private func cycleChoice(_ title: String, value: Bool) -> some View {
        let on = draft.onPeriod == value
        return Button { draft.onPeriod = on ? nil : value } label: {
            Text(title).font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(on ? (value ? theme.bad : theme.accent) : theme.track, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(on ? theme.onAccent : Color.primary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("On your period today: \(title)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func yesNoChoice(_ title: String, value: Bool, current: Bool?, tint: Color, label: String,
                             set: @escaping (Bool?) -> Void) -> some View {
        let on = current == value
        return Button { set(on ? nil : value) } label: {
            Text(title).font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(on ? (value ? tint : theme.accent) : theme.track, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(on ? (value && tint == theme.sick ? Color.black : theme.onAccent) : Color.primary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(label): \(title)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func field(_ title: String, _ text: Binding<String>, _ placeholder: String, decimal: Bool = false, health: HealthField? = nil) -> some View {
        LabeledContent {
            TextField(placeholder, text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad).multilineTextAlignment(.trailing)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let f = health { sourceTag(f) }
            }
        }
    }

    // MARK: Apple Health

    /// What Health recorded for the night, how it was scored, and why. The score fills the sleep rating below it.
    @ViewBuilder private var sleepHealthNote: some View {
        if let log = existing(date), let m = log.healthSleepMinutes {
            let res = SleepScore.score(asleepMinutes: m, awakeMinutes: log.healthSleepAwakeMinutes, deepRemMinutes: log.healthSleepDeepRemMinutes)
            let finished = SleepScore.isFinished(day: date, now: Date())
            VStack(alignment: .leading, spacing: 5) {
                switch healthSource(.sleep) {
                case .health:
                    Label("Health · \(res.headline)", systemImage: "heart.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.pink)
                case .edited:
                    HStack(spacing: 6) {
                        Text("Edited by you · Health recorded \(SleepScore.hm(m)), which scores \(res.score) of 5").font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                        if healthConnected { Button("Use Health's") { useHealths(.sleep) }.font(.caption.weight(.semibold)).buttonStyle(.borderless) }
                    }
                case .typed:
                    Label(finished ? "Health recorded \(SleepScore.hm(m)) asleep, which would score \(res.score) of 5"
                                   : "Health recorded \(SleepScore.hm(m)) asleep so far. It is scored after 11:00.",
                          systemImage: "heart.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.pink)
                }
                if finished { Text(res.detail).font(.caption).foregroundStyle(theme.muted) }
                if finished, let c = res.caveat { Text(c).font(.caption).foregroundStyle(theme.warn) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bodyCompositionText(_ log: DayLog) -> String {
        var parts: [String] = []
        if let f = log.healthBodyFat { parts.append(String(format: "Body fat %.1f%%", f)) }
        if let l = log.healthLeanKg { parts.append(String(format: "lean mass %.1f %@", unit.fromKg(l), unit.rawValue)) }
        return parts.joined(separator: " · ")
    }

    enum FieldSource { case typed, health, edited }

    /// Where a field's value comes from: Health, Health's value the user typed over, or typed.
    private func healthSource(_ f: HealthField) -> FieldSource {
        guard let log = existing(date) else { return .typed }
        if log.overridden.contains(f) { return .edited }
        if log.imported.contains(f) { return draft.text(for: f) == baseline.text(for: f) ? .health : .edited }
        return .typed
    }

    @ViewBuilder private func sourceTag(_ f: HealthField) -> some View {
        switch healthSource(f) {
        case .typed: EmptyView()
        case .health:
            Label("Health", systemImage: "heart.fill").font(.caption2.weight(.semibold)).foregroundStyle(Color.pink)
                .labelStyle(.titleAndIcon)
        case .edited:
            HStack(spacing: 6) {
                Text("Edited by you").font(.caption2.weight(.semibold)).foregroundStyle(theme.accent)
                if healthConnected { Button("Use Health's") { useHealths(f) }.font(.caption2.weight(.semibold)).buttonStyle(.borderless) }
            }
        }
    }

    /// Hand a field back to Health: clear the typed value and let the next sync fill it.
    private func useHealths(_ f: HealthField) {
        save()
        guard let log = existing(date) else { return }
        var over = log.overridden; over.remove(f); log.overridden = over
        var imp = log.imported; imp.remove(f); log.imported = imp
        var v = log.healthValues; v.clear(f); log.healthValues = v
        log.updatedAt = Date()
        try? context.save()
        load(date)
        syncHealth(force: true)
    }

    /// `overwrite`: the user pressed Sync, so Health's values replace what was typed on this day (the last action wins).
    private func syncHealth(force: Bool = false, overwrite: Bool = false) {
        guard healthConnected, !syncing else { return }
        if overwrite { save() }                                  // a half-typed edit is saved first, so this sync is the later action
        syncing = true
        let day = date
        Task {
            await HealthSync.sync(context, force: force, overwriteDay: overwrite ? day : nil, includeDay: day)
            lastSyncShown = HealthSync.lastSync
            syncing = false
            if draft == baseline { load(date) }
        }
    }

    /// "Rate it": dismiss the question, scroll to the training performance row once the banner has gone, and tint it briefly.
    private func startRating(_ log: DayLog, _ proxy: ScrollViewProxy) {
        log.healthPromptDismissed = true
        try? context.save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // the row's ForEach id: a List knows these even before the row is on screen
            withAnimation { proxy.scrollTo(Rating.performance.id, anchor: .center) }
            withAnimation { highlightPerformance = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { highlightPerformance = false } }
        }
    }

    @ViewBuilder private func healthSections(_ proxy: ScrollViewProxy) -> some View {
        if healthConnected {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").foregroundStyle(Color.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Health").font(.subheadline.weight(.semibold))
                        Text(lastSyncShown.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Not updated yet")
                            .font(.caption).foregroundStyle(theme.muted)
                    }
                    Spacer()
                    Button { syncHealth(force: true, overwrite: true) } label: {
                        if syncing { ProgressView() } else { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                    }
                    .buttonStyle(.bordered).disabled(syncing)
                }
            }
            .listRowBackground(theme.card)
        }
        if let log = existing(date), let minutes = log.healthWorkoutMinutes, !log.healthPromptDismissed,
           draft.ratings[.performance] == nil, !draft.performanceNA {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "heart.fill").foregroundStyle(Color.pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Health recorded a strength workout").font(.subheadline.weight(.semibold))
                            Text("\(minutes) minutes. Rate this day's training performance?").font(.caption).foregroundStyle(theme.muted)
                        }
                    }
                    HStack(spacing: 10) {
                        Button("Not a lifting day") {
                            draft.performanceNA = true; draft.ratings[.performance] = nil
                            log.healthPromptDismissed = true; try? context.save()
                        }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                        Button("Rate it") { startRating(log, proxy)
                        }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(theme.card)
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
        Task { await DailyReminder.refresh(context) }          // goals met today? then today's reminder is cancelled
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
