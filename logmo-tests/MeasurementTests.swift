import XCTest
import SwiftData
@testable import logmo

final class MeasurementTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }
    var container: ModelContainer?

    func camp(every: Int, start: Int = 2, weeks: Int = 8) -> CampaignInfo {
        CampaignInfo(number: 1, kind: .cut, start: day(start), plannedWeeks: weeks, measureEveryDays: every)
    }
    func entry(_ n: Int, _ v: [MeasureSite: Double]) -> MeasureEntry { MeasureEntry(day: day(n), values: v) }

    func testMeasuresRoundTripAndIgnoreJunk() {
        let m = BodyMeasures(values: [.navel: 83.5, .chest: 97])
        XCTAssertEqual(BodyMeasures(raw: m.raw), m)
        XCTAssertNil(BodyMeasures().raw)
        XCTAssertEqual(BodyMeasures(raw: "navel:83.5,bogus:1,chest:abc,thighs:-3").values, [.navel: 83.5])
        XCTAssertTrue(BodyMeasures.isPlausible(83)); XCTAssertFalse(BodyMeasures.isPlausible(0)); XCTAssertFalse(BodyMeasures.isPlausible(900))
    }

    func testCadenceNames() {
        XCTAssertEqual(MeasureCadence.allCases.map(\.title), ["Off", "Weekly", "Biweekly", "Monthly"])
        XCTAssertEqual(MeasureCadence.monthly.rawValue, 28)
        XCTAssertEqual(MeasureCadence(days: 5), .off)
    }

    func testDueDatesFollowTheCadenceFromTheStart() {
        XCTAssertEqual(MeasureRules.dueDates(camp(every: 14), through: day(30), calendar: cal), [day(2), day(16), day(30)])
        XCTAssertEqual(MeasureRules.dueDates(camp(every: 7, weeks: 2), through: day(30), calendar: cal), [day(2), day(9)])   // never past the campaign's last day (15th)
        XCTAssertEqual(MeasureRules.dueDates(camp(every: 0), through: day(30), calendar: cal), [])
        XCTAssertEqual(MeasureRules.dueDates(camp(every: 28), through: day(30), calendar: cal), [day(2), day(30)])
    }

    func testDueUntilSomethingIsMeasuredSinceTheLatestDueDate() {
        let c = camp(every: 14)
        XCTAssertTrue(MeasureRules.isDue(c, entries: [], today: day(2), calendar: cal))                    // the start day
        XCTAssertFalse(MeasureRules.isDue(c, entries: [entry(2, [.navel: 85])], today: day(10), calendar: cal))
        XCTAssertTrue(MeasureRules.isDue(c, entries: [entry(2, [.navel: 85])], today: day(16), calendar: cal))
        XCTAssertTrue(MeasureRules.isDue(c, entries: [entry(2, [.navel: 85])], today: day(18), calendar: cal))   // still due until done
        XCTAssertFalse(MeasureRules.isDue(c, entries: [entry(2, [.navel: 85]), entry(17, [.navel: 84])], today: day(18), calendar: cal))
        XCTAssertFalse(MeasureRules.isDue(camp(every: 0), entries: [], today: day(5), calendar: cal))     // off
        XCTAssertFalse(MeasureRules.isDue(c, entries: [], today: day(1), calendar: cal))                   // before the campaign
        XCTAssertEqual(MeasureRules.nextDue(c, today: day(5), calendar: cal), day(16))
        XCTAssertNil(MeasureRules.nextDue(camp(every: 14, weeks: 2), today: day(20), calendar: cal))
    }

    func testBaselineOnTheFirstDayAndAnEndStateInTheLastWeekAlways() {
        // 8 weeks from 2 Nov: last day 27 Dec, so the final week starts 21 Dec. Monthly would otherwise skip it.
        let c = camp(every: 28)
        let all = MeasureRules.dueDates(c, through: cal.date(byAdding: .day, value: 60, to: day(2))!, calendar: cal)
        XCTAssertEqual(all.first, day(2))                                                                  // the baseline
        XCTAssertEqual(all.last, cal.date(byAdding: .day, value: 49, to: day(2)))                          // the end state: the first day of the last week
        XCTAssertEqual(all.count, 3)                                                                       // start, one monthly, the end state
        // Weekly: the regular ones stop before the last week and the end-state day joins them once.
        let w = MeasureRules.dueDates(camp(every: 7), through: cal.date(byAdding: .day, value: 60, to: day(2))!, calendar: cal)
        XCTAssertEqual(w.count, 8); XCTAssertEqual(Set(w).count, 8)
        // A one-week campaign has just the one, on its first day.
        XCTAssertEqual(MeasureRules.dueDates(camp(every: 14, weeks: 1), through: day(30), calendar: cal), [day(2)])
        // Not due in the last week until that date is reached.
        let m = [entry(2, [.navel: 85]), entry(30, [.navel: 84])]
        XCTAssertFalse(MeasureRules.isDue(c, entries: m, today: cal.date(byAdding: .day, value: 48, to: day(2))!, calendar: cal))
        XCTAssertTrue(MeasureRules.isDue(c, entries: m, today: cal.date(byAdding: .day, value: 49, to: day(2))!, calendar: cal))
    }

    func testPhotosAreAskedOnTheSameDaysOnlyWhenSwitchedOn() {
        var c = camp(every: 14)
        XCTAssertFalse(MeasureRules.isPhotoDue(c, photoDays: [], today: day(2), calendar: cal))           // off
        c.photoPrompt = true
        XCTAssertTrue(MeasureRules.isPhotoDue(c, photoDays: [], today: day(2), calendar: cal))
        XCTAssertFalse(MeasureRules.isPhotoDue(c, photoDays: [day(2)], today: day(10), calendar: cal))
        XCTAssertTrue(MeasureRules.isPhotoDue(c, photoDays: [day(2)], today: day(16), calendar: cal))
        XCTAssertFalse(MeasureRules.isPhotoDue(c, photoDays: [day(2), day(16)], today: day(17), calendar: cal))
        c.measureEveryDays = 0
        XCTAssertFalse(MeasureRules.isPhotoDue(c, photoDays: [], today: day(2), calendar: cal))           // no cadence, no prompt
    }

    func testChangeNeedsTwoReadingsAWeekApart() {
        let e = [entry(2, [.navel: 85, .chest: 97]), entry(5, [.navel: 84.5]), entry(16, [.navel: 83.5, .chest: 97])]
        let ch = MeasureRules.changes(e, calendar: cal)
        XCTAssertEqual(ch[.navel]!, -1.5, accuracy: 0.001)
        XCTAssertEqual(ch[.chest]!, 0, accuracy: 0.001)
        XCTAssertNil(MeasureRules.changes([entry(2, [.navel: 85]), entry(5, [.navel: 84])], calendar: cal)[.navel])   // only 3 days apart
        XCTAssertEqual(MeasureRules.entries(e, in: camp(every: 14, weeks: 1), calendar: cal).count, 2)                  // the 16th is after a one-week campaign
    }

    // MARK: Still to log

    func testTrackerStatesAreGreyAmberGreen() {
        let goals = GoalSet(proteinDaily: 150, stepsDaily: 8000, waterDailyMl: 2200)
        func s(_ t: Tracker, logged: Set<Tracker>, complete: Set<Tracker> = [], p: Int? = nil, w: Int? = nil, st: Int? = nil) -> TrackerState {
            TrackerProgress.state(t, logged: logged, complete: complete, protein: p, water: w, steps: st, goals: goals)
        }
        XCTAssertEqual(s(.water, logged: []), .none)
        XCTAssertEqual(s(.water, logged: [.water], w: 1200), .inProgress)               // started, goal not reached
        XCTAssertEqual(s(.water, logged: [.water], w: 2200), .done)
        XCTAssertEqual(s(.steps, logged: [.steps], st: 5000), .inProgress)
        XCTAssertEqual(s(.steps, logged: [.steps], st: 9000), .done)
        XCTAssertEqual(s(.food, logged: [.food], p: 100), .inProgress)                  // some fields only
        XCTAssertEqual(s(.food, logged: [.food], complete: [.food], p: 120), .inProgress)   // complete, protein under the goal
        XCTAssertEqual(s(.food, logged: [.food], complete: [.food], p: 160), .done)
        XCTAssertEqual(s(.weight, logged: [.weight]), .done)
        XCTAssertEqual(s(.checkIn, logged: [.checkIn]), .inProgress)
        XCTAssertEqual(s(.checkIn, logged: [.checkIn], complete: [.checkIn]), .done)
        // No goal: logging it is enough.
        XCTAssertEqual(TrackerProgress.state(.water, logged: [.water], complete: [], protein: nil, water: 300, steps: nil, goals: nil), .done)
        // A weekly-average steps goal is not a daily bar.
        XCTAssertEqual(TrackerProgress.state(.steps, logged: [.steps], complete: [], protein: nil, water: nil, steps: 100,
                                             goals: GoalSet(stepsDaily: 8000, stepsIsWeeklyAverage: true)), .done)
    }

    // MARK: Storage, backup and export

    @MainActor
    func testMeasurementsAndCadenceSurviveBackupAndAppearInTheExport() throws {
        let c = try ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        container = c
        let context = c.mainContext
        let log = DayLog(day: day(5)); log.measures = BodyMeasures(values: [.navel: 83.5, .biceps: 33]); log.photosTaken = true
        context.insert(log)
        var withPhotos = camp(every: 14); withPhotos.photoPrompt = true
        context.insert(Campaign(withPhotos))
        try context.save()
        let f = try Backup.decode(try Backup.encode(try Backup.make(context)))
        try Backup.restore(f, into: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DayLog>()).first?.measures.values, [.navel: 83.5, .biceps: 33])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Campaign>()).first?.measureEveryDays, 14)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DayLog>()).first?.photosTaken, true)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Campaign>()).first?.photoPrompt, true)
        var row = log.exportRow
        row.campaign = ""
        let csv = CSVExport.render([row], calendar: cal)
        XCTAssertTrue(csv.hasPrefix(CSVExport.header))
        XCTAssertTrue(CSVExport.header.contains("measure_navel_cm") && CSVExport.header.contains("measure_biceps_cm"))
        XCTAssertTrue(csv.contains("83.5"))
        XCTAssertTrue(CSVExport.header.hasSuffix("progress_photos"))
        XCTAssertTrue(csv.split(separator: "\n")[1].hasSuffix(",true"))
    }

    @MainActor
    func testStartingACampaignKeepsItsMeasurementCadence() throws {
        let c = try ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        container = c
        let context = c.mainContext
        let r = CampaignStore.start(context, kind: .cut, targetKg: 78, start: day(20), weeks: 4, startWeightKg: 80, measureEveryDays: 28, today: day(20))
        if case .failure(let e) = r { XCTFail("start failed: \(e)") }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Campaign>()).first { !$0.isDefault }?.measureEveryDays, 28)
    }
}
