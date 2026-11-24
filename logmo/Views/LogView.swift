import SwiftUI
import SwiftData

/// Editable copy of a day. Text fields stay strings so "empty" is distinguishable from 0.
struct DayDraft: Equatable {
    var weight = ""
    var calories = ""
    var protein = ""
    var water = ""
    var ratings: [Rating: Int] = [:]

    var isEmpty: Bool {
        weight.isEmpty && calories.isEmpty && protein.isEmpty && water.isEmpty && ratings.isEmpty
    }

    init() {}

    init(_ log: DayLog?, unit: WeightUnit) {
        guard let log else { return }
        if let w = log.weightKg { weight = String(format: "%.1f", unit.fromKg(w)) }
        calories = log.calories.map(String.init) ?? ""
        protein = log.proteinG.map(String.init) ?? ""
        water = log.waterMl.map(String.init) ?? ""
        for r in Rating.allCases { if let v = log.rating(r) { ratings[r] = v } }
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
        log.waterMl = Int(water)
        for r in Rating.allCases { log.setRating(r, ratings[r]) }
        log.updatedAt = Date()
    }
}

struct LogView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @Query(sort: \DayLog.day) private var logs: [DayLog]

    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var draft = DayDraft()
    @State private var loadedDay: Date?

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private func existing(_ day: Date) -> DayLog? {
        logs.first { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless)
                        Spacer()
                        DatePicker("Date", selection: $date, in: ...today, displayedComponents: .date)
                            .labelsHidden()
                        Spacer()
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.borderless)
                            .disabled(date >= today)
                    }
                }

                Section("Weight") {
                    LabeledContent("Weight (\(unit.rawValue))") {
                        TextField("—", text: $draft.weight)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }

                Section("Food") {
                    LabeledContent("Calories (kcal)") {
                        TextField("—", text: $draft.calories)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Protein (g)") {
                        TextField("—", text: $draft.protein)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                }

                Section("Water") {
                    LabeledContent("Total (ml)") {
                        TextField("—", text: $draft.water)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        ForEach([250, 500, 750], id: \.self) { ml in
                            Button("+\(ml)") { addWater(ml) }
                                .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        }
                    }
                }

                Section("Check-in (1–5, tap again to clear)") {
                    ForEach(Rating.allCases) { r in
                        RatingRow(title: r.title, low: r.low, high: r.high, value: draft.ratings[r]) { draft.ratings[r] = $0 }
                    }
                }
            }
            .navigationTitle(date == today ? "Today" : date.formatted(date: .abbreviated, time: .omitted))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .onAppear { load(date) }
            .onChange(of: date) { old, new in save(day: old); load(new) }
            .onDisappear { save() }
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
        loadedDay = day
    }

    private func save(day: Date? = nil) {
        let d = Calendar.current.startOfDay(for: day ?? date)
        guard loadedDay.map({ Calendar.current.isDate($0, inSameDayAs: d) }) ?? false else { return }
        if let log = existing(d) {
            draft.apply(to: log, unit: unit)
        } else if !draft.isEmpty {
            let log = DayLog(day: d)
            draft.apply(to: log, unit: unit)
            context.insert(log)
        }
        try? context.save()
    }
}

struct RatingRow: View {
    let title: String
    let low: String
    let high: String
    let value: Int?
    let set: (Int?) -> Void

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
                            .background(value == n ? Color.accentColor : Color(.secondarySystemFill), in: Circle())
                            .foregroundStyle(value == n ? .white : .primary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(title) \(n): \(n == 1 ? low : n == 5 ? high : "")")
                }
                }
            }
            Text("1 = \(low) · 5 = \(high)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
