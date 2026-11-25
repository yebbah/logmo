import XCTest
import SwiftData
@testable import logmo

final class HealthMergeTests: XCTestCase {
    var cal: Calendar = Calendar.current
    var today: Date { cal.startOfDay(for: Date()) }
    let all = HealthMerge.enabledFields(Set(HealthTopic.allCases))

    /// A merge with the overridden set passed by value, as most tests want.
    @discardableResult
    func merge(_ h: HealthDay, _ v: inout HealthFieldValues, _ imp: inout Set<HealthField>, overridden: Set<HealthField> = [],
               enabled: Set<HealthField>? = nil, overwriting: Bool = false) -> Bool {
        var o = overridden
        return HealthMerge.merge(h, into: &v, imported: &imp, overridden: &o, enabled: enabled ?? all, overwriting: overwriting)
    }

    func health(weight: Double? = nil, steps: Int? = nil, water: Int? = nil, kcal: Int? = nil, protein: Int? = nil, carbs: Int? = nil, fat: Int? = nil) -> HealthDay {
        HealthDay(day: today, weightKg: weight, steps: steps, waterMl: water, calories: kcal, proteinG: protein, carbsG: carbs, fatG: fat)
    }

    func testHealthFillsEmptyFieldsAndMarksThemImported() {
        var v = HealthFieldValues(); var imp = Set<HealthField>()
        XCTAssertTrue(merge(health(weight: 81.4, steps: 9420, kcal: 2050, protein: 148), &v, &imp, overridden: [], enabled: all))
        XCTAssertEqual(v.weightKg, 81.4); XCTAssertEqual(v.steps, 9420); XCTAssertEqual(v.calories, 2050); XCTAssertEqual(v.proteinG, 148)
        XCTAssertEqual(imp, [.weight, .steps, .calories, .protein])
        XCTAssertNil(v.waterMl)                                                    // Health had none: stays empty, never zero
    }

    func testImportedValuesKeepUpdatingWhileTheDayIsOpen() {
        var v = HealthFieldValues(); var imp = Set<HealthField>()
        merge(health(steps: 3000), &v, &imp, overridden: [], enabled: all)
        XCTAssertTrue(merge(health(steps: 7200), &v, &imp, overridden: [], enabled: all))
        XCTAssertEqual(v.steps, 7200)
        XCTAssertFalse(merge(health(steps: 7200), &v, &imp, overridden: [], enabled: all))   // nothing new
    }

    func testWhatTheUserTypedIsNeverOverwritten() {
        var v = HealthFieldValues(weightKg: 82.0); var imp = Set<HealthField>()
        XCTAssertFalse(merge(health(weight: 81.4), &v, &imp, overridden: [], enabled: all))
        XCTAssertEqual(v.weightKg, 82.0); XCTAssertTrue(imp.isEmpty)
    }

    func testAHealthValueTheUserTypedOverStaysTheirs() {
        var v = HealthFieldValues(weightKg: 82.0); var imp = Set<HealthField>()
        XCTAssertFalse(merge(health(weight: 81.4), &v, &imp, overridden: [.weight], enabled: all))
        XCTAssertEqual(v.weightKg, 82.0)
        // and even when the user cleared it
        var empty = HealthFieldValues()
        XCTAssertFalse(merge(health(weight: 81.4), &empty, &imp, overridden: [.weight], enabled: all))
        XCTAssertNil(empty.weightKg)
    }

    func testZeroAndMissingAreNeverImported() {
        var v = HealthFieldValues(); var imp = Set<HealthField>()
        XCTAssertFalse(merge(health(weight: 0, steps: 0, water: 0, kcal: 0), &v, &imp, overridden: [], enabled: all))
        XCTAssertEqual(v, HealthFieldValues())
    }

    func testOnlyTheSwitchedOnTopicsAreImported() {
        var v = HealthFieldValues(); var imp = Set<HealthField>()
        let fields = HealthMerge.enabledFields([.steps])
        merge(health(weight: 81.4, steps: 9000, kcal: 2000), &v, &imp, overridden: [], enabled: fields)
        XCTAssertEqual(v.steps, 9000); XCTAssertNil(v.weightKg); XCTAssertNil(v.calories)
    }

    func testSyncOverwritesWhatWasTyped_andTheLastActionWins() {
        var v = HealthFieldValues(weightKg: 82.0, steps: 4000); var imp = Set<HealthField>(); var over: Set<HealthField> = [.weight]
        // The user pressed Sync: Health replaces the typed weight, even one they had typed over before.
        XCTAssertTrue(HealthMerge.merge(health(weight: 81.4, steps: 9000), into: &v, imported: &imp, overridden: &over, enabled: all, overwriting: true))
        XCTAssertEqual(v.weightKg, 81.4); XCTAssertEqual(v.steps, 9000)
        XCTAssertEqual(imp, [.weight, .steps]); XCTAssertTrue(over.isEmpty)
        // They then type a new weight: that is the later action, so it stands against a normal refresh.
        let old = v; v.weightKg = 82.5
        HealthMerge.markEdits(old: old, new: v, imported: &imp, overridden: &over)
        XCTAssertFalse(HealthMerge.merge(health(weight: 81.4), into: &v, imported: &imp, overridden: &over, enabled: all))
        XCTAssertEqual(v.weightKg, 82.5)
        // Pressing Sync again is later still, so Health wins again.
        XCTAssertTrue(HealthMerge.merge(health(weight: 81.4), into: &v, imported: &imp, overridden: &over, enabled: all, overwriting: true))
        XCTAssertEqual(v.weightKg, 81.4)
    }

    func testOverwriteLeavesFieldsHealthHasNothingFor() {
        var v = HealthFieldValues(weightKg: 82.0, waterMl: 1800); var imp = Set<HealthField>()
        merge(health(steps: 9000), &v, &imp, overwriting: true)
        XCTAssertEqual(v.weightKg, 82.0); XCTAssertEqual(v.waterMl, 1800); XCTAssertEqual(v.steps, 9000)
        merge(health(weight: 0, water: 0), &v, &imp, overwriting: true)                      // zero is no reading
        XCTAssertEqual(v.weightKg, 82.0); XCTAssertEqual(v.waterMl, 1800)
    }

    func testEditingAnImportedFieldMakesItTheUsers() {
        let old = HealthFieldValues(weightKg: 81.4, steps: 9420)
        var new = old; new.weightKg = 82.0
        var imp: Set<HealthField> = [.weight, .steps], over = Set<HealthField>()
        HealthMerge.markEdits(old: old, new: new, imported: &imp, overridden: &over)
        XCTAssertEqual(imp, [.steps]); XCTAssertEqual(over, [.weight])
        var cleared = old; cleared.steps = nil                                       // clearing counts as the user's choice too
        HealthMerge.markEdits(old: old, new: cleared, imported: &imp, overridden: &over)
        XCTAssertEqual(over, [.weight, .steps])
    }

    func testMarkersRoundTrip() {
        let s: Set<HealthField> = [.carbs, .weight]
        XCTAssertEqual(HealthMerge.decode(HealthMerge.encode(s)), s)
        XCTAssertEqual(HealthMerge.decode(""), [])
    }
}

@MainActor
final class HealthSyncTests: XCTestCase {
    var container: ModelContainer?
    func makeContext() throws -> ModelContext {
        let c = try ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container = c; return c.mainContext
    }
    var today: Date { Calendar.current.startOfDay(for: Date()) }
    func day(_ back: Int) -> Date { Calendar.current.date(byAdding: .day, value: -back, to: today)! }
    let topics = Set(HealthTopic.allCases)

    func testSyncCreatesLogsOnlyForDaysWithData_andNeverForTheFuture() throws {
        let context = try makeContext()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        HealthSync.apply([HealthDay(day: today, steps: 5000), HealthDay(day: day(1)), HealthDay(day: tomorrow, steps: 100)], to: context, topics: topics, today: today)
        let logs = try context.fetch(FetchDescriptor<DayLog>())
        XCTAssertEqual(logs.count, 1); XCTAssertEqual(logs[0].steps, 5000); XCTAssertEqual(logs[0].imported, [.steps])
    }

    func testSyncUpdatesImportedValuesButNotTypedOnes() throws {
        let context = try makeContext()
        let log = DayLog(day: today); log.weightKg = 82.0; context.insert(log); try context.save()
        HealthSync.apply([HealthDay(day: today, weightKg: 81.4, steps: 3000)], to: context, topics: topics, today: today)
        XCTAssertEqual(log.weightKg, 82.0); XCTAssertEqual(log.steps, 3000)
        HealthSync.apply([HealthDay(day: today, weightKg: 81.4, steps: 8000)], to: context, topics: topics, today: today)
        XCTAssertEqual(log.steps, 8000); XCTAssertEqual(log.weightKg, 82.0)
    }

    func testTypingOverAnImportedValueStopsFurtherUpdates() throws {
        let context = try makeContext()
        HealthSync.apply([HealthDay(day: today, steps: 3000)], to: context, topics: topics, today: today)
        let log = try context.fetch(FetchDescriptor<DayLog>())[0]
        var d = DayDraft(log, unit: .kg); d.steps = "4000"
        d.apply(to: log, unit: .kg)                                                  // what Log's autosave does
        XCTAssertEqual(log.steps, 4000); XCTAssertEqual(log.overridden, [.steps]); XCTAssertTrue(log.imported.isEmpty)
        HealthSync.apply([HealthDay(day: today, steps: 9000)], to: context, topics: topics, today: today)
        XCTAssertEqual(log.steps, 4000)
    }

    func testPressingSyncOverwritesTheViewedDayOnly() throws {
        let context = try makeContext()
        let log = DayLog(day: today); log.weightKg = 82.0; log.steps = 4000; context.insert(log)
        let yesterday = DayLog(day: day(1)); yesterday.weightKg = 83.0; context.insert(yesterday); try context.save()
        let h = [HealthDay(day: today, weightKg: 81.4, steps: 9000), HealthDay(day: day(1), weightKg: 80.9)]
        HealthSync.apply(h, to: context, topics: topics, today: today, overwriteDay: today)
        XCTAssertEqual(log.weightKg, 81.4); XCTAssertEqual(log.steps, 9000)
        XCTAssertEqual(yesterday.weightKg, 83.0)                                         // another day keeps what was typed
        // A normal refresh afterwards does not undo a later manual edit.
        var d = DayDraft(log, unit: .kg); d.weight = "82.5"; d.apply(to: log, unit: .kg)
        HealthSync.apply(h, to: context, topics: topics, today: today)
        XCTAssertEqual(log.weightKg, 82.5)
    }

    func testStrengthWorkoutMinutesAreRecordedForTheQuestion() throws {
        let context = try makeContext()
        HealthSync.apply([HealthDay(day: today, strengthMinutes: 52)], to: context, topics: topics, today: today)
        let log = try context.fetch(FetchDescriptor<DayLog>())[0]
        XCTAssertEqual(log.healthWorkoutMinutes, 52)
        XCTAssertNil(log.sleep); XCTAssertFalse(log.performanceNA)                    // nothing is rated for the user
        XCTAssertFalse(log.healthPromptDismissed)
    }

    func testImportedValuesCountLikeTypedOnes() throws {
        let context = try makeContext()
        HealthSync.apply([HealthDay(day: today, weightKg: 81.4, steps: 9000, waterMl: 2500, calories: 2000, proteinG: 150, carbsG: 200, fatG: 60)],
                         to: context, topics: topics, today: today)
        let snap = try context.fetch(FetchDescriptor<DayLog>())[0].snapshot
        XCTAssertTrue(snap.complete.isSuperset(of: [.weight, .food, .water, .steps]))
    }

    func testBackupKeepsWhichValuesCameFromHealth() throws {
        let context = try makeContext()
        HealthSync.apply([HealthDay(day: today, weightKg: 81.4, steps: 3000)], to: context, topics: topics, today: today)
        let log = try context.fetch(FetchDescriptor<DayLog>())[0]
        log.overridden = [.weight]; log.imported = [.steps]
        let data = try Backup.encode(try Backup.make(context))
        try DataReset.deleteAll(context)
        try Backup.restore(try Backup.decode(data), into: context)
        let back = try context.fetch(FetchDescriptor<DayLog>())[0]
        XCTAssertEqual(back.imported, [.steps]); XCTAssertEqual(back.overridden, [.weight])
    }
}
