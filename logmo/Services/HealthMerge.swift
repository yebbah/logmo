import Foundation

/// The fields Apple Health can fill. Each can come from Health, from the user, or be a Health value the user typed over.
enum HealthField: String, CaseIterable {
    case weight, calories, protein, carbs, fat, water, steps
}

/// What the user can switch on in Settings → Apple Health.
enum HealthTopic: String, CaseIterable, Identifiable {
    case weight, steps, water, food, workouts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weight: "Weight"
        case .steps: "Steps"
        case .water: "Water"
        case .food: "Food"
        case .workouts: "Strength workouts"
        }
    }
    var detail: String {
        switch self {
        case .weight: "Body mass, from a smart scale or any app that writes it"
        case .steps: "The day's step total"
        case .water: "Needs an app that writes water to Health"
        case .food: "Calories, protein, carbs and fat. Needs a nutrition app that writes to Health"
        case .workouts: "Suggests a lifting day; you decide what to rate"
        }
    }
    var fields: [HealthField] {
        switch self {
        case .weight: [.weight]
        case .steps: [.steps]
        case .water: [.water]
        case .food: [.calories, .protein, .carbs, .fat]
        case .workouts: []
        }
    }
}

/// What Health holds for one day. A value that isn't there is nil; a zero is never imported.
struct HealthDay: Equatable {
    var day: Date
    var weightKg: Double?
    var steps: Int?
    var waterMl: Int?
    var calories: Int?
    var proteinG: Int?
    var carbsG: Int?
    var fatG: Int?
    var strengthMinutes: Int?

    var isEmpty: Bool {
        weightKg == nil && steps == nil && waterMl == nil && calories == nil && proteinG == nil && carbsG == nil && fatG == nil && strengthMinutes == nil
    }
}

/// A day's values for the fields Health can fill.
struct HealthFieldValues: Equatable {
    var weightKg: Double?
    var calories: Int?
    var proteinG: Int?
    var carbsG: Int?
    var fatG: Int?
    var waterMl: Int?
    var steps: Int?

    mutating func clear(_ f: HealthField) {
        switch f {
        case .weight: weightKg = nil
        case .calories: calories = nil
        case .protein: proteinG = nil
        case .carbs: carbsG = nil
        case .fat: fatG = nil
        case .water: waterMl = nil
        case .steps: steps = nil
        }
    }

    func isSet(_ f: HealthField) -> Bool {
        switch f {
        case .weight: weightKg != nil
        case .calories: calories != nil
        case .protein: proteinG != nil
        case .carbs: carbsG != nil
        case .fat: fatG != nil
        case .water: waterMl != nil
        case .steps: steps != nil
        }
    }
}

enum HealthMerge {
    static func encode(_ s: Set<HealthField>) -> String { HealthField.allCases.filter(s.contains).map(\.rawValue).joined(separator: ",") }
    static func decode(_ raw: String) -> Set<HealthField> { Set(raw.split(separator: ",").compactMap { HealthField(rawValue: String($0)) }) }

    /// Health's value for a field, only if it is a real reading (never zero or missing).
    static func value(_ f: HealthField, in h: HealthDay) -> Double? {
        let v: Double?
        switch f {
        case .weight: v = h.weightKg
        case .calories: v = h.calories.map(Double.init)
        case .protein: v = h.proteinG.map(Double.init)
        case .carbs: v = h.carbsG.map(Double.init)
        case .fat: v = h.fatG.map(Double.init)
        case .water: v = h.waterMl.map(Double.init)
        case .steps: v = h.steps.map(Double.init)
        }
        guard let v, v > 0 else { return nil }
        return v
    }

    /// Bring Health's values into a day. What the user typed always wins: a field is taken only if it is empty or is
    /// already a Health value, and never if the user typed over Health's value (`overridden`). Returns whether anything changed.
    @discardableResult
    static func merge(_ h: HealthDay, into v: inout HealthFieldValues, imported: inout Set<HealthField>,
                      overridden: Set<HealthField>, enabled: Set<HealthField>) -> Bool {
        var changed = false
        for f in HealthField.allCases where enabled.contains(f) && !overridden.contains(f) {
            guard let hv = value(f, in: h) else { continue }
            guard !v.isSet(f) || imported.contains(f) else { continue }          // typed by the user: theirs stays
            let before = v
            switch f {
            case .weight: v.weightKg = hv
            case .calories: v.calories = Int(hv.rounded())
            case .protein: v.proteinG = Int(hv.rounded())
            case .carbs: v.carbsG = Int(hv.rounded())
            case .fat: v.fatG = Int(hv.rounded())
            case .water: v.waterMl = Int(hv.rounded())
            case .steps: v.steps = Int(hv.rounded())
            }
            if v != before { changed = true }
            if !imported.contains(f) { imported.insert(f); changed = true }
        }
        return changed
    }

    /// After the user saves a day: any Health value they changed or cleared is now theirs.
    static func markEdits(old: HealthFieldValues, new: HealthFieldValues, imported: inout Set<HealthField>, overridden: inout Set<HealthField>) {
        for f in HealthField.allCases where imported.contains(f) {
            let same: Bool
            switch f {
            case .weight: same = abs((old.weightKg ?? -1) - (new.weightKg ?? -1)) < 0.0005
            case .calories: same = old.calories == new.calories
            case .protein: same = old.proteinG == new.proteinG
            case .carbs: same = old.carbsG == new.carbsG
            case .fat: same = old.fatG == new.fatG
            case .water: same = old.waterMl == new.waterMl
            case .steps: same = old.steps == new.steps
            }
            if !same { imported.remove(f); overridden.insert(f) }
        }
    }

    /// The fields to import for the topics the user switched on.
    static func enabledFields(_ topics: Set<HealthTopic>) -> Set<HealthField> { Set(topics.flatMap(\.fields)) }
}
