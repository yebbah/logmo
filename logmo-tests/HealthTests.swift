import XCTest
import SwiftData
@testable import logmo

final class HealthMergeTests: XCTestCase {
    var cal: Calendar = Calendar.current
    var today: Date { cal.startOfDay(for: Date()) }
    let all = HealthMerge.enabledFields(Set(HealthTopic.allCases))

    func health(weight: Double? = nil, steps: Int? = nil, water: Int? = nil, kcal: Int? = nil, protein: Int? = nil, carbs: Int? = nil, fat: Int? = nil) -> HealthDay {
        HealthDay(day: today, weightKg: weight, steps: steps, waterMl: water, calories: kcal, proteinG: protein, carbsG: carbs, fatG: fat)
    }

    func testHealthFillsEmptyFieldsAndMarksThemImported() {
        var v = HealthFieldValues(); var imp = Set<HealthField>()
        XCTAssertTrue(HealthMerge.merge(health(weight: 81.4, steps: 9420, kcal: 2050, protein: 148), into: &v, imported: &imp, overridden: [], enabled: all))
        XCTAssertEqual(v.weightKg, 81.4); XCTAssertEqual(v.steps, 9420); XCTAssertEqual(v.calories, 2050); XCTAssertEqual(v.proteinG, 148)
        XCTAssertEqual(imp, [.weight, .steps, .calories, .protein])
        XCTAssertNil(v.waterMl)                                                    // Health had none: stays empty, never zero
    }

    func testImportedValuesKeepUpdatingWhileTheDayIsOpen() {
        var v = HealthFieldValues(); var imp = Set<HealthField>()
        HealthMerge.merge(health(steps: 3000), into: &v, imported: &imp, overridden: [], enabled: all)
        XCTAssertTrue(HealthMerge.merge(health(steps: 7200), into: &v, imported: &imp, overridden: [], enabled: all))
        XCTAssertEqual(v.steps, 7200)
        XCTAssertFalse(HealthMerge.merge(health(steps: 7200), into: &v, imported: &imp, overridden: [], enabled: all))   // nothing new
    }

    func testWhatTheUserTypedIsNeverOverwritten() {
        var v = HealthFieldValues(weightKg: 82.0); var imp = Set<HealthField>()
        XCTAssertFalse(HealthMerge.merge(health(weight: 81.4), into: &v, imported: &imp, overridden: [], enabled: all))
        XCTAssertEqual(v.weightKg, 82.0); XCTAssertTrue(imp.isEmpty)
    }

    func testAHealthValueTheUserTypedOverStaysTheirs() {
        var v = HealthFieldValues(weightKg: 82.0); var imp = Set<HealthField>()
        XCTAssertFalse(HealthMerge.merge(health(weight: 81.4), into: &v, imported: &imp, overridden: [.weight], enabled: all))
        XCTAssertEqual(v.weightKg, 82.0)
        // and even when the user cleared it
        var empty = HealthFieldValues()
        XCTAssertFalse(HealthMerge.merge(health(weight: 81.4), into: &empty, imported: &imp, overridden: [.weight], enabled: all))
        XCTAssertNil(empty.weightKg)
    }

    func testZeroAndMissingAreNeverImported() {
        var v = HealthFieldValues(); var imp = Set<HealthField>()
        XCTAssertFalse(HealthMerge.merge(health(weight: 0, steps: 0, water: 0, kcal: 0), into: &v, imported: &imp, overridden: [], enabled: all))
        XCTAssertEqual(v, HealthFieldValues())
    }

    func testOnlyTheSwitchedOnTopicsAreImported() {
        var v = HealthFieldValues(); var imp = Set<HealthField>()
        let fields = HealthMerge.enabledFields([.steps])
        HealthMerge.merge(health(weight: 81.4, steps: 9000, kcal: 2000), into: &v, imported: &imp, overridden: [], enabled: fields)
        XCTAssertEqual(v.steps, 9000); XCTAssertNil(v.weightKg); XCTAssertNil(v.calories)
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
