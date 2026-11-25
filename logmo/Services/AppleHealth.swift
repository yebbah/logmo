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
         quantity(.dietaryProtein), quantity(.dietaryCarbohydrates), quantity(.dietaryFatTotal), HKObjectType.workoutType(),
         HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!, HKObjectType.categoryType(forIdentifier: .menstrualFlow)!,
         quantity(.restingHeartRate), quantity(.heartRateVariabilitySDNN), quantity(.bodyFatPercentage), quantity(.leanBodyMass)]
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
            for (d, v) in await latest(.bodyMass, .gramUnit(with: .kilo), start, end) { edit(d) { $0.weightKg = v } }
        }
        if topics.contains(.body) {
            for (d, v) in await latest(.bodyFatPercentage, .percent(), start, end) where v > 0 { edit(d) { $0.bodyFatPercent = v * 100 } }
            for (d, v) in await latest(.leanBodyMass, .gramUnit(with: .kilo), start, end) { edit(d) { $0.leanKg = v } }
        }
        if topics.contains(.recovery) {
            for (d, v) in await averages(.restingHeartRate, HKUnit.count().unitDivided(by: .minute()), start, end) { edit(d) { $0.restingHR = Int(v.rounded()) } }
            for (d, v) in await averages(.heartRateVariabilitySDNN, .secondUnit(with: .milli), start, end) { edit(d) { $0.hrv = Int(v.rounded()) } }
        }
        if topics.contains(.sleep) {
            for (d, m) in await sleepMinutes(start, end) { edit(d) { $0.sleepMinutes = m } }
        }
        if topics.contains(.cycle) {
            for d in await periodDays(start, end) { edit(d) { $0.periodDay = true } }
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

    /// The last reading of each day of a quantity (weight, body fat, lean mass).
    private static func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ start: Date, _ end: Date) async -> [Date: Double] {
        let cal = Calendar.current
        let from = cal.startOfDay(for: start)
        let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: quantity(id), predicate: HKQuery.predicateForSamples(withStart: from, end: to),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, samples, _ in
                var out: [Date: Double] = [:]
                for s in (samples as? [HKQuantitySample]) ?? [] {
                    out[cal.startOfDay(for: s.endDate)] = s.quantity.doubleValue(for: unit)     // ascending: the last one wins
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// Daily averages of a quantity (resting heart rate, HRV).
    private static func averages(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ start: Date, _ end: Date) async -> [Date: Double] {
        let cal = Calendar.current
        let from = cal.startOfDay(for: start)
        let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: quantity(id), quantitySamplePredicate: HKQuery.predicateForSamples(withStart: from, end: to),
                                                options: .discreteAverage, anchorDate: from, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, _ in
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: from, to: to) { s, _ in
                    if let v = s.averageQuantity()?.doubleValue(for: unit), v > 0 { out[s.startDate] = v }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// Minutes asleep for each day (credited to the day the sleep ended). Overlapping records from a watch and a
    /// phone are merged, so the same night isn't counted twice. Time in bed and awake time don't count.
    private static func sleepMinutes(_ start: Date, _ end: Date) async -> [Date: Int] {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: start))!
        let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                                  predicate: HKQuery.predicateForSamples(withStart: from, end: to), limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                var byDay: [Date: [(Date, Date)]] = [:]
                for s in (samples as? [HKCategorySample]) ?? [] where asleep.contains(s.value) {
                    byDay[cal.startOfDay(for: s.endDate), default: []].append((s.startDate, s.endDate))
                }
                var out: [Date: Int] = [:]
                for (day, spans) in byDay {
                    var total: TimeInterval = 0
                    var cur: (Date, Date)?
                    for sp in spans.sorted(by: { $0.0 < $1.0 }) {
                        if let c = cur, sp.0 <= c.1 { cur = (c.0, max(c.1, sp.1)) }
                        else { if let c = cur { total += c.1.timeIntervalSince(c.0) }; cur = sp }
                    }
                    if let c = cur { total += c.1.timeIntervalSince(c.0) }
                    let m = Int((total / 60).rounded())
                    if m > 0 { out[day] = m }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// Days Health has menstrual flow recorded (light, medium, heavy or unspecified; "none" doesn't count).
    private static func periodDays(_ start: Date, _ end: Date) async -> Set<Date> {
        let cal = Calendar.current
        let from = cal.startOfDay(for: start)
        let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.categoryType(forIdentifier: .menstrualFlow)!,
                                  predicate: HKQuery.predicateForSamples(withStart: from, end: to), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                var out = Set<Date>()
                for s in (samples as? [HKCategorySample]) ?? [] where (1...4).contains(s.value) { out.insert(cal.startOfDay(for: s.startDate)) }
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
    /// Bumped whenever the app starts reading another type of data, so an existing connection asks iOS about it once.
    static let currentAuthVersion = 2
    static let authVersion = "healthAuthVersion"
    static func key(_ t: HealthTopic) -> String { "health.\(t.rawValue)" }
    static func isOn(_ t: HealthTopic, _ d: UserDefaults = .standard) -> Bool { d.object(forKey: key(t)) as? Bool ?? t.defaultOn }
    static func topics(_ d: UserDefaults = .standard) -> Set<HealthTopic> { Set(HealthTopic.allCases.filter { isOn($0, d) }) }
}

/// Merges Health's values into the day logs. Typed values are never overwritten; nothing is imported as zero.
@MainActor
enum HealthSync {
    /// Last time a sync ran, for "Updated 8:12" and to avoid hammering Health.
    static var lastSync: Date? { (UserDefaults.standard.object(forKey: HealthSettings.lastSync) as? Double).map(Date.init(timeIntervalSince1970:)) }

    /// Pull the last week from Health (when connected and at least `minInterval` seconds since the last pull) and merge it.
    @discardableResult
    /// The days to read: the last `days` ending today, stretched back to include `includeDay` (an older day the user is looking at).
    static func window(now: Date, days: Int, includeDay: Date?, calendar cal: Calendar = .current) -> (start: Date, end: Date) {
        let today = cal.startOfDay(for: now)
        var start = cal.date(byAdding: .day, value: -(max(days, 1) - 1), to: today)!
        if let d = includeDay.map({ cal.startOfDay(for: $0) }), d < start { start = d }
        return (start, today)
    }

    /// `includeDay`: an older day to read as well (the one open on the Log screen); `days`: how far back to read in all.
    static func sync(_ context: ModelContext, force: Bool = false, overwriteDay: Date? = nil, includeDay: Date? = nil, minInterval: TimeInterval = 20, days: Int = 7, now: Date = Date()) async -> Bool {
        let d = UserDefaults.standard
        guard d.bool(forKey: HealthSettings.connected), AppleHealth.isAvailable else { return false }
        if d.integer(forKey: HealthSettings.authVersion) < HealthSettings.currentAuthVersion {       // new types since last asked: iOS only prompts for those
            try? await AppleHealth.requestAuthorization()
            d.set(HealthSettings.currentAuthVersion, forKey: HealthSettings.authVersion)
        }
        if !force, let last = lastSync, now.timeIntervalSince(last) < minInterval { return false }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let (start, _) = window(now: now, days: days, includeDay: includeDay ?? overwriteDay, calendar: cal)
        var topics = HealthSettings.topics(d)
        if !d.bool(forKey: SettingsKey.trackCycle) { topics.remove(.cycle) }      // cycle only when cycle tracking is on
        let fetched = await AppleHealth.days(from: start, to: today, topics: topics)
        apply(fetched, to: context, topics: topics, today: today, overwriteDay: overwriteDay)
        d.set(now.timeIntervalSince1970, forKey: HealthSettings.lastSync)
        await DailyReminder.refresh(context)
        return true
    }

    /// The merge, separate from the fetching so it can be tested without Health.
    /// `overwriteDay`: the day the user pressed Sync on; Health's values replace what was typed there (last action wins).
    static func apply(_ days: [HealthDay], to context: ModelContext, topics: Set<HealthTopic>, today: Date, overwriteDay: Date? = nil) {
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
            var overridden = log.overridden
            let overwrite = overwriteDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
            let changed = HealthMerge.merge(h, into: &values, imported: &imported, overridden: &overridden, enabled: enabled, overwriting: overwrite)
            var workout = false
            if topics.contains(.workouts), let m = h.strengthMinutes, log.healthWorkoutMinutes != m { log.healthWorkoutMinutes = m; workout = true }
            var derived = false
            func setIf<T: Equatable>(_ on: Bool, _ new: T?, _ cur: T?, _ assign: (T?) -> Void) {
                if on, let new, new != cur { assign(new); derived = true }
            }
            setIf(topics.contains(.sleep), h.sleepMinutes, log.healthSleepMinutes) { log.healthSleepMinutes = $0 }
            setIf(topics.contains(.recovery), h.restingHR, log.healthRestingHR) { log.healthRestingHR = $0 }
            setIf(topics.contains(.recovery), h.hrv, log.healthHRV) { log.healthHRV = $0 }
            setIf(topics.contains(.body), h.bodyFatPercent, log.healthBodyFat) { log.healthBodyFat = $0 }
            setIf(topics.contains(.body), h.leanKg, log.healthLeanKg) { log.healthLeanKg = $0 }
            guard changed || workout || derived else { continue }
            log.healthValues = values
            log.imported = imported
            log.overridden = overridden
            log.updatedAt = Date()
            if existing == nil { context.insert(log) }
            touched = true
        }
        if touched { try? context.save() }
    }
}
