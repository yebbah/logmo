import Foundation

// Extension points. Nothing implements these yet; the app is local-only today.
// Keeping them here means Apple Health and cloud sync can be added without touching
// the views or the metrics code.

/// A value read from an external source for a given day.
struct ExternalSample: Equatable {
    var day: Date
    var weightKg: Double?
    var waterMl: Int?
    var calories: Int?
    var proteinG: Int?
    var fatG: Int?
    var carbsG: Int?
    var steps: Int?
    var source: String
}

/// Apple Health (HealthKit) will conform to this. Imports should be written into
/// DayLog with `weightSource = "healthkit"`, and must not overwrite a manual value
/// the user has entered for that day.
protocol HealthSource {
    func requestAuthorization() async throws
    func samples(from: Date, to: Date) async throws -> [ExternalSample]
}

/// A flat, Codable copy of DayLog for sending over the wire.
struct DayRecord: Codable, Equatable {
    var id: UUID
    var day: Date
    var updatedAt: Date
    var weightKg: Double?
    var calories: Int?
    var proteinG: Int?
    var fatG: Int?
    var carbsG: Int?
    var waterMl: Int?
    var steps: Int?
    var performanceNA: Bool = false
    var onPeriod: Bool?
    var ratings: [String: Int]
}

/// A cloud backend (CloudKit, Supabase, …) will conform to this.
protocol SyncBackend {
    func push(_ records: [DayRecord]) async throws
    func pull(since: Date?) async throws -> [DayRecord]
}
