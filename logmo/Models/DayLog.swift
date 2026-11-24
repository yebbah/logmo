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
    var waterMl: Int?

    var sleep: Int?
    var fatigue: Int?
    var stress: Int?
    var hunger: Int?
    var performance: Int?
    var appetite: Int?
    var soreness: Int?

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

    var loggedTrackers: Set<Tracker> {
        var s: Set<Tracker> = []
        if weightKg != nil { s.insert(.weight) }
        if calories != nil || proteinG != nil { s.insert(.food) }
        if waterMl != nil { s.insert(.water) }
        if Rating.allCases.contains(where: { rating($0) != nil }) { s.insert(.checkIn) }
        return s
    }

    var snapshot: DaySnapshot {
        DaySnapshot(date: day, weightKg: weightKg, logged: loggedTrackers)
    }
}
