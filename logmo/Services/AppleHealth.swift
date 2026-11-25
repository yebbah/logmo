import Foundation
import HealthKit
import SwiftData

/// Reads from Apple Health. logmo never writes to it. The values come back as `HealthDay`s, and `HealthSync` merges them.
enum AppleHealth {
    private static let store = HKHealthStore()
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static func quantity(_ id: HKQuantityTypeIdentifier) -> HKQuantityType { HKQuantityType(id) }

    static var readTypes: Set<HKObjectType> {
        [quantity(.bodyMass), quantity(.stepCount), quantity(.dietaryWater), quantity(.dietaryEnergyConsumed),
         quantity(.dietaryProtein), quantity(.dietaryCarbohydrates), quantity(.dietaryFatTotal), HKObjectType.workoutType()]
    }

    /// Asks iOS for read access, one type at a time in its own sheet. Declined types look like "no data".
    static func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Health's values for the days from `start` to `end`, for the topics switched on.
    static func days(from start: Date, to end: Date, topics: Set<HealthTopic>) async -> [HealthDay] {
        guard isAvailable else { return [] }
        let cal = Calendar.current
        var byDay: [Date: HealthDay] = [:]
        func edit(_ d: Date, _ change: (inout HealthDay) -> Void) {
            let k = cal.startOfDay(for: d)
            var h = byDay[k] ?? HealthDay(day: k)
            change(&h); byDay[k] = h
        }
        if topics.contains(.steps) {
            for (d, v) in await sums(.stepCount, .count(), start, end) { edit(d) { $0.steps = Int(v.rounded()) } }
        }
        if topics.contains(.water) {
            for (d, v) in await sums(.dietaryWater, .literUnit(with: .milli), start, end) { edit(d) { $0.waterMl = Int(v.rounded()) } }
        }
        if topics.contains(.food) {
            for (d, v) in await sums(.dietaryEnergyConsumed, .kilocalorie(), start, end) { edit(d) { $0.calories = Int(v.rounded()) } }
            for (d, v) in await sums(.dietaryProtein, .gram(), start, end) { edit(d) { $0.proteinG = Int(v.rounded()) } }
            for (d, v) in await sums(.dietaryCarbohydrates, .gram(), start, end) { edit(d) { $0.carbsG = Int(v.rounded()) } }
            for (d, v) in await sums(.dietaryFatTotal, .gram(), start, end) { edit(d) { $0.fatG = Int(v.rounded()) } }
        }
        if topics.contains(.weight) {
            for (d, v) in await latestWeights(start, end) { edit(d) { $0.weightKg = v } }
        }
        if topics.contains(.workouts) {
            for (d, m) in await strengthMinutes(start, end) { edit(d) { $0.strengthMinutes = m } }
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    // MARK: Queries

    /// Daily totals of a cumulative quantity (steps, water, nutrition).
    private static func sums(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ start: Date, _ end: Date) async -> [Date: Double] {
        let cal = Calendar.current
        let from = cal.startOfDay(for: start)
        let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: quantity(id),
                                                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: from, end: to),
                                                options: .cumulativeSum, anchorDate: from, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, _ in
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: from, to: to) { s, _ in
                    if let v = s.sumQuantity()?.doubleValue(for: unit), v > 0 { out[s.startDate] = v }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// The last weigh-in of each day, in kg.
    private static func latestWeights(_ start: Date, _ end: Date) async -> [Date: Double] {
        let cal = Calendar.current
        let from = cal.startOfDay(for: start)
        let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: quantity(.bodyMass), predicate: HKQuery.predicateForSamples(withStart: from, end: to),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, samples, _ in
                var out: [Date: Double] = [:]
                for s in (samples as? [HKQuantitySample]) ?? [] {
                    out[cal.startOfDay(for: s.endDate)] = s.quantity.doubleValue(for: .gramUnit(with: .kilo))     // ascending: the last one wins
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// Minutes of strength training recorded each day.
    private static func strengthMinutes(_ start: Date, _ end: Date) async -> [Date: Int] {
        let cal = Calendar.current
        let from = cal.startOfDay(for: start)
        let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!
        let types = NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .traditionalStrengthTraining), HKQuery.predicateForWorkouts(with: .functionalStrengthTraining)])
        let when = HKQuery.predicateForSamples(withStart: from, end: to)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [types, when]),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                var out: [Date: Int] = [:]
                for w in (samples as? [HKWorkout]) ?? [] {
                    out[cal.startOfDay(for: w.startDate), default: 0] += max(Int((w.duration / 60).rounded()), 1)
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }
}

/// Settings for the Health connection, kept in UserDefaults like the other preferences.
enum HealthSettings {
    static let connected = "healthConnected"
    static let lastSync = "healthLastSync"
    static func key(_ t: HealthTopic) -> String { "health.\(t.rawValue)" }
    static func isOn(_ t: HealthTopic, _ d: UserDefaults = .standard) -> Bool { d.object(forKey: key(t)) as? Bool ?? true }
    static func topics(_ d: UserDefaults = .standard) -> Set<HealthTopic> { Set(HealthTopic.allCases.filter { isOn($0, d) }) }
}

/// Merges Health's values into the day logs. Typed values are never overwritten; nothing is imported as zero.
@MainActor
enum HealthSync {
    /// Last time a sync ran, for "Updated 8:12" and to avoid hammering Health.
    static var lastSync: Date? { (UserDefaults.standard.object(forKey: HealthSettings.lastSync) as? Double).map(Date.init(timeIntervalSince1970:)) }

    /// Pull the last week from Health (when connected and at least `minInterval` seconds since the last pull) and merge it.
    @discardableResult
    static func sync(_ context: ModelContext, force: Bool = false, minInterval: TimeInterval = 20, days: Int = 7, now: Date = Date()) async -> Bool {
        let d = UserDefaults.standard
        guard d.bool(forKey: HealthSettings.connected), AppleHealth.isAvailable else { return false }
        if !force, let last = lastSync, now.timeIntervalSince(last) < minInterval { return false }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -(days - 1), to: today)!
        let topics = HealthSettings.topics(d)
        let fetched = await AppleHealth.days(from: start, to: today, topics: topics)
        apply(fetched, to: context, topics: topics, today: today)
        d.set(now.timeIntervalSince1970, forKey: HealthSettings.lastSync)
        await DailyReminder.refresh(context)
        return true
    }

    /// The merge, separate from the fetching so it can be tested without Health.
    static func apply(_ days: [HealthDay], to context: ModelContext, topics: Set<HealthTopic>, today: Date) {
        let cal = Calendar.current
        let logs = (try? context.fetch(FetchDescriptor<DayLog>())) ?? []
        let enabled = HealthMerge.enabledFields(topics)
        var touched = false
        for h in days where !h.isEmpty && cal.startOfDay(for: h.day) <= today {
            let day = cal.startOfDay(for: h.day)
            let existing = logs.first { cal.isDate($0.day, inSameDayAs: day) }
            let log = existing ?? DayLog(day: day)
            var values = log.healthValues
            var imported = log.imported
            let changed = HealthMerge.merge(h, into: &values, imported: &imported, overridden: log.overridden, enabled: enabled)
            var workout = false
            if topics.contains(.workouts), let m = h.strengthMinutes, log.healthWorkoutMinutes != m { log.healthWorkoutMinutes = m; workout = true }
            guard changed || workout else { continue }
            log.healthValues = values
            log.imported = imported
            log.updatedAt = Date()
            if existing == nil { context.insert(log) }
            touched = true
        }
        if touched { try? context.save() }
    }
}
