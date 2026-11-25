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
                           waterMl: waterMl, steps: steps, ratings: r, performanceNA: performanceNA)
    }

    var exportRow: ExportRow {
        var r: [String: Int] = [:]
        for k in Rating.allCases { if let v = rating(k) { r[k.rawValue] = v } }
        return ExportRow(day: day, weightKg: weightKg, calories: calories, proteinG: proteinG,
                         fatG: fatG, carbsG: carbsG, waterMl: waterMl, steps: steps, ratings: r,
                         performanceNA: performanceNA)
    }
}
