import XCTest
@testable import logmo

final class CampaignTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }

    func real(_ n: Int, start: Int, weeks: Int, end: Int? = nil, early: Bool = false) -> CampaignInfo {
        CampaignInfo(number: n, kind: .cut, start: day(start), plannedWeeks: weeks, end: end.map(day), endedEarly: early)
    }
    func dflt(_ n: Int, start: Int, end: Int? = nil) -> CampaignInfo {
        CampaignInfo(number: n, kind: .maintenance, isDefault: true, start: day(start), end: end.map(day))
    }

    func testPlannedEndAndDaysLeft() {
        let c = real(1, start: 2, weeks: 2)                       // 2 Nov … 15 Nov
        XCTAssertEqual(CampaignRules.plannedEnd(c, calendar: cal), day(15))
        XCTAssertEqual(CampaignRules.daysLeft(c, today: day(2), calendar: cal), 14)    // first day of 2 weeks: 14 left
        XCTAssertEqual(CampaignRules.daysLeft(c, today: day(3), calendar: cal), 13)    // counts down daily
        XCTAssertEqual(CampaignRules.daysLeft(c, today: day(15), calendar: cal), 1)    // last planned day
        XCTAssertEqual(CampaignRules.daysLeft(c, today: day(16), calendar: cal), 0)    // over
        XCTAssertEqual(CampaignRules.daysLeft(c, today: day(20), calendar: cal), 0)    // never negative
        XCTAssertEqual(CampaignRules.daysLeft(real(2, start: 2, weeks: 4), today: day(2), calendar: cal), 28)
        XCTAssertNil(CampaignRules.daysLeft(dflt(2, start: 2), today: day(5), calendar: cal))  // default has no end
    }
    func testFiveWeekCampaign() {
        let c = real(1, start: 2, weeks: 5)                       // 2 Nov + 35 days, last day 6 Dec
        XCTAssertEqual(CampaignRules.plannedEnd(c, calendar: cal), cal.date(from: DateComponents(year: 2026, month: 12, day: 6)))
    }
    func testWeekNumber() {
        let c = real(1, start: 2, weeks: 3)
        XCTAssertEqual(CampaignRules.weekNumber(c, today: day(2), calendar: cal), 1)
        XCTAssertEqual(CampaignRules.weekNumber(c, today: day(8), calendar: cal), 1)
        XCTAssertEqual(CampaignRules.weekNumber(c, today: day(9), calendar: cal), 2)
        XCTAssertEqual(CampaignRules.weekNumber(c, today: day(29), calendar: cal), 3)   // clamped to the planned length
    }
    func testEveryDayBelongsToOneCampaign() {
        let all = [dflt(1, start: 1, end: 9), real(2, start: 10, weeks: 2, end: 16, early: true), dflt(3, start: 17)]
        XCTAssertEqual(CampaignRules.campaign(for: day(9), in: all, calendar: cal)?.number, 1)
        XCTAssertEqual(CampaignRules.campaign(for: day(10), in: all, calendar: cal)?.number, 2)
        XCTAssertEqual(CampaignRules.campaign(for: day(16), in: all, calendar: cal)?.number, 2)
        XCTAssertEqual(CampaignRules.campaign(for: day(17), in: all, calendar: cal)?.number, 3)
        XCTAssertEqual(CampaignRules.campaign(for: day(25), in: all, calendar: cal)?.number, 3)   // open-ended
        XCTAssertNil(CampaignRules.campaign(for: day(1) .addingTimeInterval(-86400 * 5), in: all, calendar: cal))
    }

    // MARK: default campaign
    func testDefaultCreatedWhenNothingExists() {
        let d = CampaignRules.defaultNeeded(existing: [], earliestLog: day(5), today: day(20), calendar: cal)!
        XCTAssertEqual(d.number, 1); XCTAssertEqual(d.kind, .maintenance); XCTAssertTrue(d.isDefault)
        XCTAssertEqual(d.start, day(5))
        XCTAssertEqual(CampaignRules.defaultNeeded(existing: [], earliestLog: nil, today: day(20), calendar: cal)!.start, day(20))
    }
    func testNoDefaultWhileSomethingIsOpen() {
        XCTAssertNil(CampaignRules.defaultNeeded(existing: [real(1, start: 2, weeks: 4)], earliestLog: nil, today: day(5), calendar: cal))
    }
    func testDefaultFollowsAnEndedCampaignWithNextNumber() {
        let ended = real(1, start: 2, weeks: 4, end: 12, early: true)
        let d = CampaignRules.defaultNeeded(existing: [ended], earliestLog: day(2), today: day(12), calendar: cal)!
        XCTAssertEqual(d.number, 2); XCTAssertEqual(d.start, day(13))
    }

    // MARK: starting
    func testStartClosesTheDefaultTheDayBefore() {
        let plan = try! CampaignRules.plan(start: day(10), kind: .cut, targetKg: 70, weeks: 8,
                                           existing: [dflt(1, start: 1)], calendar: cal).get()
        XCTAssertEqual(plan.new.number, 2); XCTAssertEqual(plan.new.targetWeightKg, 70)
        XCTAssertEqual(plan.endDefault?.on, day(9))
        XCTAssertNil(plan.deleteDefault)
    }
    func testStartingOnTheDefaultsFirstDayReplacesIt() {
        let existing = [dflt(1, start: 5)]
        let plan = try! CampaignRules.plan(start: day(5), kind: .bulk, targetKg: nil, weeks: 4, existing: existing, calendar: cal).get()
        XCTAssertEqual(plan.deleteDefault, existing[0].id)
        XCTAssertEqual(plan.new.number, 1)                  // the discarded default's number is reused
    }
    func testCannotStartWhileARealCampaignRuns() {
        let r = CampaignRules.plan(start: day(20), kind: .cut, targetKg: nil, weeks: 4,
                                   existing: [real(1, start: 2, weeks: 8)], calendar: cal)
        XCTAssertEqual(r, .failure(.campaignRunning))
    }
    func testCannotStartBeforeCurrentOrOverlapPrevious() {
        XCTAssertEqual(CampaignRules.plan(start: day(3), kind: .cut, targetKg: nil, weeks: 4,
                                          existing: [dflt(2, start: 10)], calendar: cal), .failure(.startsBeforeCurrent))
        XCTAssertEqual(CampaignRules.plan(start: day(3), kind: .cut, targetKg: nil, weeks: 0,
                                          existing: [], calendar: cal), .failure(.invalidWeeks))
    }
    func testNumbersIncrementAcrossHistory() {
        let hist = [dflt(1, start: 1, end: 9), real(2, start: 10, weeks: 4, end: 20), dflt(3, start: 21)]
        let plan = try! CampaignRules.plan(start: day(25), kind: .bulk, targetKg: nil, weeks: 6, existing: hist, calendar: cal).get()
        XCTAssertEqual(plan.new.number, 4)
        XCTAssertEqual(plan.endDefault?.on, day(24))
    }

    // MARK: ending
    func testEndingEarlyAndOnTime() {
        let c = real(1, start: 2, weeks: 4)                     // planned end 29 Nov
        XCTAssertEqual(CampaignRules.ending(c, on: day(12), calendar: cal).early, true)
        XCTAssertEqual(CampaignRules.ending(c, on: day(29), calendar: cal).early, false)
        XCTAssertEqual(CampaignRules.ending(c, on: day(1), calendar: cal).end, day(2))   // never before its own start
    }

    // MARK: future start
    func testAFutureStartKeepsTheDefaultRunningUntilThen() {
        let existing = [dflt(1, start: 2)]
        let plan = try! CampaignRules.plan(start: day(20), kind: .bulk, targetKg: 85, weeks: 12, existing: existing, calendar: cal).get()
        XCTAssertEqual(plan.endDefault?.on, day(19))                  // the default ends the day before the new one starts
        XCTAssertTrue(CampaignRules.isUpcoming(plan.new, today: day(10), calendar: cal))
        XCTAssertFalse(CampaignRules.isUpcoming(plan.new, today: day(20), calendar: cal))
        XCTAssertEqual(CampaignRules.daysUntilStart(plan.new, today: day(10), calendar: cal), 10)
        // Until the start date, today still belongs to the default.
        let all = [CampaignInfo(id: existing[0].id, number: 1, kind: .maintenance, isDefault: true, start: day(2), end: day(19)), plan.new]
        XCTAssertEqual(CampaignRules.campaign(for: day(10), in: all, calendar: cal)?.number, 1)
        XCTAssertEqual(CampaignRules.campaign(for: day(20), in: all, calendar: cal)?.number, 2)
        // No second default is created while the upcoming campaign is open.
        XCTAssertNil(CampaignRules.defaultNeeded(existing: all, earliestLog: nil, today: day(10), calendar: cal))
    }
    func testCancellingAnUpcomingCampaignReopensTheDefault() {
        let d = dflt(1, start: 2, end: 19)
        let up = real(2, start: 20, weeks: 8)
        XCTAssertEqual(CampaignRules.defaultToReopen(cancelling: up, existing: [d, up], calendar: cal), d.id)
        XCTAssertNil(CampaignRules.defaultToReopen(cancelling: up, existing: [up], calendar: cal))
    }
    func testOnlyOneRealCampaignEvenIfItIsUpcoming() {
        let up = real(2, start: 20, weeks: 8)
        XCTAssertEqual(CampaignRules.plan(start: day(25), kind: .cut, targetKg: nil, weeks: 4, existing: [dflt(1, start: 2, end: 19), up], calendar: cal),
                       .failure(.campaignRunning))
    }
}
