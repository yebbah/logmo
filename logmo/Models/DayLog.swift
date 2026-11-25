import Foundation
import SwiftData

/// Subjective 1–5 ratings carried over from the workbook's Data Input tab.
/// The workbook doesn't define the scale, so the anchors below are ours (PRD v1.1).
/// Direction differs by category: for sleep and performance 5 is good; for
/// fatigue, stress, hunger and soreness 5 is "more". Always show the anchors.
enum Rating: String, CaseIterable, Identifiable {
    case sleep, fatigue, stress, hunger, performance, appetite, soreness
    var id: String { rawValue }
    var title: String {
        switch self {
        case .performance: "Training performance"
        default: rawValue.capitalized
        }
    }

    /// Meaning of 1.
    var low: String {
        switch self {
        case .sleep: "Lowest quality"
        case .fatigue: "Fresh, no fatigue"
        case .stress: "Calm, no stress"
        case .hunger: "Not hungry"
        case .performance: "Very poor session"
        case .appetite: "No appetite"
        case .soreness: "Not sore"
        }
    }

    /// Meaning of 5.
    var high: String {
        switch self {
        case .sleep: "Best quality"
        case .fatigue: "Exhausted"
        case .stress: "Extremely stressed"
        case .hunger: "Ravenous"
        case .performance: "Excellent, a best"
        case .appetite: "Very strong appetite"
        case .soreness: "Severe, can't train"
        }
    }
}

/// One row per calendar day. Every property is optional or defaulted and there are
/// no unique constraints, so the model can later be synced with CloudKit unchanged.
/// "Missing" is nil, never zero.
@Model
final class DayLog {
    var id: UUID = UUID()
    var day: Date = Date()            // start of day, local calendar
    var updatedAt: Date = Date()      // for last-write-wins sync later

    var weightKg: Double?
    var weightSource: String = "manual"   // "manual" now; "healthkit" later

    var calories: Int?
    var proteinG: Int?
    var fatG: Int?
    var carbsG: Int?
    var waterMl: Int?
    var steps: Int?

    var sleep: Int?
    var fatigue: Int?
    var stress: Int?
    var hunger: Int?
    var performance: Int?
    var appetite: Int?
    var soreness: Int?
    var performanceNA: Bool = false       // training performance answered "n/a": not a lifting day
    var onPeriod: Bool?                   // "on your period today?" nil = not answered; only asked if cycle tracking is on
    var isSick: Bool?                     // "are you sick today?" nil = not answered; only asked if sick tracking is on
    var importedFields: String = ""       // fields currently holding a value from Apple Health (HealthField names)
    var overriddenFields: String = ""     // Health fields the user typed over: Health no longer touches them
    var healthWorkoutMinutes: Int?        // minutes of strength training Health recorded that day
    var healthPromptDismissed: Bool = false   // the "rate today's training?" question was answered
    var healthSleepMinutes: Int?          // asleep time Health recorded; scored into the sleep rating
    var healthSleepAwakeMinutes: Int?     // awake time during the night, when Health has it
    var healthSleepDeepRemMinutes: Int?   // deep plus REM, when Health has sleep stages
    var healthRestingHR: Int?             // bpm
    var healthHRV: Int?                   // SDNN, ms
    var healthBodyFat: Double?            // percent
    var healthLeanKg: Double?

    init(day: Date) {
        self.day = Calendar.current.startOfDay(for: day)
    }

    func rating(_ r: Rating) -> Int? {
        switch r {
        case .sleep: sleep
        case .fatigue: fatigue
        case .stress: stress
        case .hunger: hunger
        case .performance: performance
        case .appetite: appetite
        case .soreness: soreness
        }
    }

    func setRating(_ r: Rating, _ v: Int?) {
        switch r {
        case .sleep: sleep = v
        case .fatigue: fatigue = v
        case .stress: stress = v
        case .hunger: hunger = v
        case .performance: performance = v
        case .appetite: appetite = v
        case .soreness: soreness = v
        }
    }

    /// Trackers with anything entered.
    var loggedTrackers: Set<Tracker> {
        var s: Set<Tracker> = []
        if weightKg != nil { s.insert(.weight) }
        if calories != nil || proteinG != nil || fatG != nil || carbsG != nil { s.insert(.food) }
        if waterMl != nil { s.insert(.water) }
        if steps != nil { s.insert(.steps) }
        if performanceNA || Rating.allCases.contains(where: { rating($0) != nil }) { s.insert(.checkIn) }
        return s
    }

    /// Trackers with every field entered: food needs all four macros, check-in all seven ratings.
    var completeTrackers: Set<Tracker> {
        var s: Set<Tracker> = []
        if weightKg != nil { s.insert(.weight) }
        if calories != nil && proteinG != nil && fatG != nil && carbsG != nil { s.insert(.food) }
        if waterMl != nil { s.insert(.water) }
        if steps != nil { s.insert(.steps) }
        // n/a counts as an answer for training performance (a rest day is still a complete check-in).
        if Rating.allCases.allSatisfy({ rating($0) != nil || ($0 == .performance && performanceNA) }) { s.insert(.checkIn) }
        return s
    }

    var snapshot: DaySnapshot {
        var r: [String: Int] = [:]
        for k in Rating.allCases { if let v = rating(k) { r[k.rawValue] = v } }
        return DaySnapshot(date: day, weightKg: weightKg, logged: loggedTrackers,
                           complete: completeTrackers, calories: calories, proteinG: proteinG,
                           carbsG: carbsG, fatG: fatG, waterMl: waterMl, steps: steps, ratings: r, performanceNA: performanceNA, onPeriod: onPeriod == true, isSick: isSick == true,
                           restingHR: healthRestingHR, hrv: healthHRV, sleepMinutes: healthSleepMinutes)
    }

    var healthValues: HealthFieldValues {
        get { HealthFieldValues(weightKg: weightKg, calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG, waterMl: waterMl, steps: steps,
                                onPeriod: onPeriod, sleep: sleep) }          // a typed "No" counts as typed: Health doesn't overwrite it
        set { weightKg = newValue.weightKg; calories = newValue.calories; proteinG = newValue.proteinG; carbsG = newValue.carbsG
              fatG = newValue.fatG; waterMl = newValue.waterMl; steps = newValue.steps
              onPeriod = newValue.onPeriod; sleep = newValue.sleep }
    }
    var imported: Set<HealthField> {
        get { HealthMerge.decode(importedFields) }
        set { importedFields = HealthMerge.encode(newValue) }
    }
    var overridden: Set<HealthField> {
        get { HealthMerge.decode(overriddenFields) }
        set { overriddenFields = HealthMerge.encode(newValue) }
    }

    var exportRow: ExportRow {
        var r: [String: Int] = [:]
        for k in Rating.allCases { if let v = rating(k) { r[k.rawValue] = v } }
        return ExportRow(day: day, weightKg: weightKg, calories: calories, proteinG: proteinG,
                         fatG: fatG, carbsG: carbsG, waterMl: waterMl, steps: steps, ratings: r,
                         performanceNA: performanceNA, onPeriod: onPeriod, isSick: isSick, sleepMinutes: healthSleepMinutes,
                         restingHR: healthRestingHR, hrv: healthHRV, bodyFatPercent: healthBodyFat, leanKg: healthLeanKg)
    }
}
