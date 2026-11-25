import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A full backup: every log, weekly goal and campaign in one JSON file, so a lost or replaced
/// phone doesn't lose the history. (The CSV export stays for spreadsheets; it holds logs only.)
struct BackupFile: Codable, Equatable {
    var version = 2
    var exportedAt = Date()
    var logs: [LogRecord] = []
    var goals: [GoalRecord] = []
    var campaigns: [CampaignRecord] = []
    var settings: [String: String] = [:]      // units, theme, required trackers, reminder, cycle … (absent in version 1)

    /// Preferences stored in UserDefaults that belong in a backup. Strings only, so any value type round-trips.
    static let settingKeys = [SettingsKey.unit, SettingsKey.smoothing, SettingsKey.required, SettingsKey.bioOverlay,
                              SettingsKey.bioShown, MaintenanceProfile.sexKey, MaintenanceProfile.ageKey, MaintenanceProfile.heightKey, MaintenanceProfile.activityKey, SettingsKey.theme, SettingsKey.trackCycle, SettingsKey.trackSick, SettingsKey.dailyReminderOn, SettingsKey.dailyReminderMinutes, SettingsKey.reminderOn,
                              SettingsKey.reminderWeekday, SettingsKey.reminderMinutes, "campaignFilter"]

    struct LogRecord: Codable, Equatable {
        var id: UUID; var day: Date; var updatedAt: Date
        var weightKg: Double?; var weightSource: String
        var calories, proteinG, fatG, carbsG, waterMl, steps: Int?
        var sleep, fatigue, stress, hunger, performance, appetite, soreness: Int?
        var performanceNA: Bool; var onPeriod: Bool?; var isSick: Bool?; var importedFields, overriddenFields: String?
        var healthSleepMinutes, healthSleepAwakeMinutes, healthSleepDeepMinutes, healthSleepREMMinutes, healthRestingHR, healthHRV: Int?; var healthBodyFat, healthLeanKg: Double?
    }
    struct GoalRecord: Codable, Equatable {
        var id: UUID; var campaignID: UUID?; var weekStart: Date; var updatedAt: Date
        var caloriesWeekly: Int?; var caloriesAtOrUnder: Bool
        var proteinDaily, stepsDaily: Int?; var stepsIsWeeklyAverage: Bool
        var workoutDaysWeekly: Int?; var confirmed: Bool; var waterDailyMl: Int?; var carbsDaily, fatDaily: Int?
    }
    struct CampaignRecord: Codable, Equatable {
        var id: UUID; var number: Int; var kindRaw: String; var isDefault: Bool
        var targetWeightKg: Double?; var start: Date; var plannedWeeks: Int?
        var end: Date?; var endedEarly: Bool; var label: String?; var updatedAt: Date
    }
}

@MainActor
enum Backup {
    static func make(_ context: ModelContext) throws -> BackupFile {
        var f = BackupFile()
        f.logs = try context.fetch(FetchDescriptor<DayLog>(sortBy: [SortDescriptor(\.day)])).map {
            .init(id: $0.id, day: $0.day, updatedAt: $0.updatedAt, weightKg: $0.weightKg, weightSource: $0.weightSource,
                  calories: $0.calories, proteinG: $0.proteinG, fatG: $0.fatG, carbsG: $0.carbsG, waterMl: $0.waterMl, steps: $0.steps,
                  sleep: $0.sleep, fatigue: $0.fatigue, stress: $0.stress, hunger: $0.hunger, performance: $0.performance,
                  appetite: $0.appetite, soreness: $0.soreness, performanceNA: $0.performanceNA, onPeriod: $0.onPeriod, isSick: $0.isSick,
                  importedFields: $0.importedFields, overriddenFields: $0.overriddenFields,
                  healthSleepMinutes: $0.healthSleepMinutes, healthSleepAwakeMinutes: $0.healthSleepAwakeMinutes,
                  healthSleepDeepMinutes: $0.healthSleepDeepMinutes, healthSleepREMMinutes: $0.healthSleepREMMinutes, healthRestingHR: $0.healthRestingHR, healthHRV: $0.healthHRV,
                  healthBodyFat: $0.healthBodyFat, healthLeanKg: $0.healthLeanKg)
        }
        f.goals = try context.fetch(FetchDescriptor<WeekGoal>(sortBy: [SortDescriptor(\.weekStart)])).map {
            .init(id: $0.id, campaignID: $0.campaignID, weekStart: $0.weekStart, updatedAt: $0.updatedAt,
                  caloriesWeekly: $0.caloriesWeekly, caloriesAtOrUnder: $0.caloriesAtOrUnder, proteinDaily: $0.proteinDaily,
                  stepsDaily: $0.stepsDaily, stepsIsWeeklyAverage: $0.stepsIsWeeklyAverage, workoutDaysWeekly: $0.workoutDaysWeekly,
                  confirmed: $0.confirmed, waterDailyMl: $0.waterDailyMl, carbsDaily: $0.carbsDaily, fatDaily: $0.fatDaily)
        }
        f.campaigns = try context.fetch(FetchDescriptor<Campaign>(sortBy: [SortDescriptor(\.number)])).map {
            .init(id: $0.id, number: $0.number, kindRaw: $0.kindRaw, isDefault: $0.isDefault, targetWeightKg: $0.targetWeightKg,
                  start: $0.start, plannedWeeks: $0.plannedWeeks, end: $0.end, endedEarly: $0.endedEarly,
                  label: $0.label, updatedAt: $0.updatedAt)
        }
        for k in BackupFile.settingKeys {
            if let v = UserDefaults.standard.object(forKey: k) { f.settings[k] = "\(v)" }
        }
        return f
    }

    static func encode(_ f: BackupFile) throws -> Data {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(f)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode(BackupFile.self, from: data)
    }

    /// Replaces everything on the phone with the backup's contents.
    static func restore(_ f: BackupFile, into context: ModelContext) throws {
        for x in try context.fetch(FetchDescriptor<DayLog>()) { context.delete(x) }
        for x in try context.fetch(FetchDescriptor<WeekGoal>()) { context.delete(x) }
        for x in try context.fetch(FetchDescriptor<Campaign>()) { context.delete(x) }
        for r in f.logs {
            let l = DayLog(day: r.day); l.id = r.id; l.day = r.day; l.updatedAt = r.updatedAt
            l.weightKg = r.weightKg; l.weightSource = r.weightSource
            l.calories = r.calories; l.proteinG = r.proteinG; l.fatG = r.fatG; l.carbsG = r.carbsG
            l.waterMl = r.waterMl; l.steps = r.steps
            l.sleep = r.sleep; l.fatigue = r.fatigue; l.stress = r.stress; l.hunger = r.hunger
            l.performance = r.performance; l.appetite = r.appetite; l.soreness = r.soreness
            l.performanceNA = r.performanceNA; l.onPeriod = r.onPeriod; l.isSick = r.isSick
            l.importedFields = r.importedFields ?? ""; l.overriddenFields = r.overriddenFields ?? ""
            l.healthSleepAwakeMinutes = r.healthSleepAwakeMinutes; l.healthSleepDeepMinutes = r.healthSleepDeepMinutes; l.healthSleepREMMinutes = r.healthSleepREMMinutes
            l.healthSleepMinutes = r.healthSleepMinutes; l.healthRestingHR = r.healthRestingHR; l.healthHRV = r.healthHRV
            l.healthBodyFat = r.healthBodyFat; l.healthLeanKg = r.healthLeanKg
            context.insert(l)
        }
        for r in f.goals {
            let g = WeekGoal(weekStart: r.weekStart, campaignID: r.campaignID); g.id = r.id; g.updatedAt = r.updatedAt
            g.caloriesWeekly = r.caloriesWeekly; g.caloriesAtOrUnder = r.caloriesAtOrUnder; g.proteinDaily = r.proteinDaily
            g.stepsDaily = r.stepsDaily; g.stepsIsWeeklyAverage = r.stepsIsWeeklyAverage
            g.workoutDaysWeekly = r.workoutDaysWeekly; g.confirmed = r.confirmed; g.waterDailyMl = r.waterDailyMl; g.carbsDaily = r.carbsDaily; g.fatDaily = r.fatDaily
            context.insert(g)
        }
        for r in f.campaigns {
            let c = Campaign(CampaignInfo(id: r.id, number: r.number, kind: CampaignKind(rawValue: r.kindRaw) ?? .maintenance,
                                          isDefault: r.isDefault, targetWeightKg: r.targetWeightKg, start: r.start,
                                          plannedWeeks: r.plannedWeeks, end: r.end, endedEarly: r.endedEarly, label: r.label))
            c.updatedAt = r.updatedAt
            context.insert(c)
        }
        try context.save()
        // Preferences. Keep each value's original type: bools and ints are stored as such.
        let d = UserDefaults.standard
        for (k, v) in f.settings where BackupFile.settingKeys.contains(k) {
            if v == "true" || v == "false" { d.set(v == "true", forKey: k) }
            else if let i = Int(v) { d.set(i, forKey: k) }
            else { d.set(v, forKey: k) }
        }
        CampaignStore.ensureDefault(context)
    }
}

/// Lets ShareLink offer the backup as a file.
struct BackupDocument: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("logmo-backup.json")
    }
}
