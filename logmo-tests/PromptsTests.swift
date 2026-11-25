import XCTest
import SwiftData
@testable import logmo

final class PromptsTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }

    func testNeedsCampaignOnlyWithoutARealOneRunningOrUpcoming() {
        let def = CampaignInfo(number: 1, kind: .maintenance, isDefault: true, start: day(1))
        XCTAssertTrue(SetupRules.needsCampaign([def], today: day(10), calendar: cal))
        let real = CampaignInfo(number: 2, kind: .cut, start: day(5), plannedWeeks: 4)
        XCTAssertFalse(SetupRules.needsCampaign([def, real], today: day(10), calendar: cal))
        let upcoming = CampaignInfo(number: 2, kind: .cut, start: day(20), plannedWeeks: 4)
        XCTAssertFalse(SetupRules.needsCampaign([def, upcoming], today: day(10), calendar: cal))
        let closed = CampaignInfo(number: 2, kind: .cut, start: day(1), plannedWeeks: 1, end: day(7))
        XCTAssertTrue(SetupRules.needsCampaign([def, closed], today: day(10), calendar: cal))
    }

    func testSetupStepsAreOffered_inOrder() {
        let def = CampaignInfo(number: 1, kind: .maintenance, isDefault: true, start: day(1))
        let real = CampaignInfo(number: 2, kind: .bulk, start: day(5), plannedWeeks: 4)
        XCTAssertEqual(SetupRules.next(campaigns: [def], hasConfirmedGoals: true, logCount: 3, today: day(10), calendar: cal), .campaign)
        XCTAssertEqual(SetupRules.next(campaigns: [def, real], hasConfirmedGoals: false, logCount: 3, today: day(10), calendar: cal), .goals)
        XCTAssertEqual(SetupRules.next(campaigns: [def, real], hasConfirmedGoals: true, logCount: 0, today: day(10), calendar: cal), .firstLog)
        XCTAssertNil(SetupRules.next(campaigns: [def, real], hasConfirmedGoals: true, logCount: 1, today: day(10), calendar: cal))
    }

    func testFinishedCampaign() {
        let c = CampaignInfo(number: 2, kind: .cut, start: day(2), plannedWeeks: 1)         // last planned day: 8 Nov
        XCTAssertFalse(SetupRules.isFinished(c, today: day(8), calendar: cal))
        XCTAssertTrue(SetupRules.isFinished(c, today: day(9), calendar: cal))
        var closed = c; closed.end = day(8)
        XCTAssertFalse(SetupRules.isFinished(closed, today: day(9), calendar: cal))
        XCTAssertFalse(SetupRules.isFinished(CampaignInfo(number: 1, kind: .maintenance, isDefault: true, start: day(1)), today: day(9), calendar: cal))
    }

    func testDraftCompleteness() {
        var d = DayDraft()
        XCTAssertTrue(d.completeTrackers.isEmpty)
        d.weight = "80"; d.calories = "2000"; d.protein = "150"; d.fat = "60"
        XCTAssertEqual(d.completeTrackers, [.weight])                     // food still needs carbs
        d.carbs = "200"; d.water = "2500"; d.steps = "9000"
        for r in Rating.allCases where r != .performance { d.ratings[r] = 3 }
        XCTAssertEqual(d.completeTrackers, [.weight, .food, .water, .steps])   // performance unanswered
        d.performanceNA = true
        XCTAssertEqual(d.completeTrackers, Set(Tracker.allCases))
    }

    @MainActor func testFinishAndExtend() throws {
        let container = try ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -10, to: today)!         // 1 planned week, over 3 days ago
        let c = Campaign(CampaignInfo(number: 1, kind: .cut, start: start, plannedWeeks: 1))
        context.insert(c); try context.save()
        XCTAssertTrue(SetupRules.isFinished(c.info, today: today))

        XCTAssertTrue(CampaignStore.extend(context, c, byWeeks: 2))
        XCTAssertEqual(c.plannedWeeks, 3); XCTAssertFalse(SetupRules.isFinished(c.info, today: today))

        c.plannedWeeks = 1
        CampaignStore.finish(context, c, today: today)
        XCTAssertEqual(c.end, CampaignRules.plannedEnd(CampaignInfo(number: 1, kind: .cut, start: start, plannedWeeks: 1)))
        XCTAssertFalse(c.endedEarly)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Campaign>()).contains { $0.isDefault && $0.end == nil })   // default carries on
    }
}

final class ExportTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }

    func testDayRowCarriesCampaignAndGoals() {
        var r = ExportRow(day: day(4), weightKg: 80, calories: nil, proteinG: nil, fatG: nil, carbsG: nil, waterMl: nil, steps: nil, ratings: [:])
        r.campaignNumber = 2; r.campaign = "Lean, bulk"; r.campaignKind = "bulk"
        r.goals = GoalSet(caloriesWeekly: 14000, proteinDaily: 150, stepsDaily: 9000, stepsIsWeeklyAverage: true, workoutDaysWeekly: 4)
        let line = CSVExport.render([r], calendar: cal).split(separator: "\n")[1]
        XCTAssertTrue(line.hasSuffix(",2,\"Lean, bulk\",bulk,2000,at_or_under,150,9000,weekly_average,,4,,"), String(line))
    }

    func testCampaignsAndGoalsFiles() {
        let c = CampaignInfo(number: 3, kind: .cut, targetWeightKg: 75, start: day(2), plannedWeeks: 4, end: day(29), label: "Summer")
        XCTAssertEqual(CSVExport.campaignsCSV([c], calendar: cal),
                       "number,name,kind,automatic_default,target_weight_kg,start,planned_weeks,end,ended_early\n3,Summer,cut,false,75.0,2026-11-02,4,2026-11-29,false\n")
        let g = CSVExport.weeklyGoalsCSV([(campaign: c, week: day(2), goals: GoalSet(proteinDaily: 140), confirmed: false)], calendar: cal)
        XCTAssertTrue(g.hasSuffix("3,Summer,2026-11-02,,,140,,,,,,,false\n"), g)
    }
}

final class DailyReminderTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))! }
    let goals = GoalSet(proteinDaily: 140, stepsDaily: 8000)

    func snap(weight: Double? = 80, protein: Int? = 150, steps: Int? = 9000) -> DaySnapshot {
        DaySnapshot(date: at(10, 0), weightKg: weight, logged: Set(Tracker.allCases), complete: Set(Tracker.allCases), proteinG: protein, steps: steps)
    }

    func testReminderIsNeededUntilTheDailyGoalsAreMet() {
        XCTAssertTrue(DailyReminderRules.needsReminder(day: nil, goals: goals, required: []))
        XCTAssertTrue(DailyReminderRules.needsReminder(day: snap(protein: 100), goals: goals, required: []))
        XCTAssertTrue(DailyReminderRules.needsReminder(day: snap(weight: nil), goals: goals, required: []))      // no weigh-in yet
        XCTAssertFalse(DailyReminderRules.needsReminder(day: snap(), goals: goals, required: []))
    }

    func testWithoutDailyGoalsItFollowsTheRequiredTrackers() {
        let none = GoalSet(caloriesWeekly: 14000)
        var partial = snap(); partial.complete = [.weight]
        XCTAssertTrue(DailyReminderRules.needsReminder(day: partial, goals: none, required: [.weight, .food]))
        XCTAssertFalse(DailyReminderRules.needsReminder(day: partial, goals: none, required: [.weight]))
        XCTAssertTrue(DailyReminderRules.needsReminder(day: nil, goals: nil, required: []))                       // nothing required: wants anything logged
        XCTAssertFalse(DailyReminderRules.needsReminder(day: snap(), goals: nil, required: []))
    }

    func testFireDatesCoverAWeekAndSkipTodayWhenDoneOrPast() {
        let now = at(10, 15)                                                          // 15:00, reminder at 20:00
        let all = DailyReminderRules.fireDates(now: now, minutes: 20 * 60, todayNeedsReminder: true, calendar: cal)
        XCTAssertEqual(all.count, 7); XCTAssertEqual(all.first, at(10, 20)); XCTAssertEqual(all.last, at(16, 20))
        let done = DailyReminderRules.fireDates(now: now, minutes: 20 * 60, todayNeedsReminder: false, calendar: cal)
        XCTAssertEqual(done.count, 6); XCTAssertEqual(done.first, at(11, 20))         // today's cancelled, tomorrow's kept
        let late = DailyReminderRules.fireDates(now: at(10, 21), minutes: 20 * 60, todayNeedsReminder: true, calendar: cal)
        XCTAssertEqual(late.first, at(11, 20)); XCTAssertEqual(late.count, 6)         // today's time has passed
    }
}
