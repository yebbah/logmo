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
        XCTAssertEqual(CampaignRules.campaign(for: day(25), in: all, calendar: cal)?.number, 3)
        XCTAssertNil(CampaignRules.campaign(for: day(1) .addingTimeInterval(-86400 * 5), in: all, calendar: cal))
    }

    // MARK: no automatic campaign, nothing open-ended
    func testACampaignCoversItsStartToItsLastDayAndNothingAfter() {
        let c = real(1, start: 2, weeks: 2)                                            // days 2 to 15
        XCTAssertEqual(CampaignRules.lastDay(c, calendar: cal), day(15))
        XCTAssertNotNil(CampaignRules.campaign(for: day(15), in: [c], calendar: cal))
        XCTAssertNil(CampaignRules.campaign(for: day(16), in: [c], calendar: cal))     // the planned days are over: no campaign covers it
        var ended = c; ended.end = day(9); ended.endedEarly = true
        XCTAssertEqual(CampaignRules.lastDay(ended, calendar: cal), day(9))
        XCTAssertNil(CampaignRules.campaign(for: day(10), in: [ended], calendar: cal))
    }
    func testDaysBetweenCampaignsBelongToNone() {
        let a = real(1, start: 2, weeks: 1, end: 8), b = real(2, start: 20, weeks: 2)
        XCTAssertNil(CampaignRules.campaign(for: day(12), in: [a, b], calendar: cal))
        XCTAssertEqual(CampaignRules.campaign(for: day(20), in: [a, b], calendar: cal)?.number, 2)
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
    func testCannotStartInsideARunningCampaignsPlannedDays() {
        // 8 weeks from day 2 runs to day 57; a new one has to start after that (it is queued behind it).
        let r = CampaignRules.plan(start: day(20), kind: .cut, targetKg: nil, weeks: 4,
                                   existing: [real(1, start: 2, weeks: 8)], today: day(10), calendar: cal)
        XCTAssertEqual(r, .failure(.startsBeforeCurrent))
        let queued = try! CampaignRules.plan(start: day(58), kind: .cut, targetKg: nil, weeks: 4,
                                             existing: [real(1, start: 2, weeks: 8)], today: day(10), calendar: cal).get()
        XCTAssertEqual(queued.new.number, 2)
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
        // Until the start date, today belongs to no campaign: nothing is created to fill the days.
        XCTAssertNil(CampaignRules.campaign(for: day(10), in: [plan.new], calendar: cal))
        XCTAssertEqual(CampaignRules.campaign(for: day(20), in: [plan.new], calendar: cal)?.number, 2)
    }
    func testOnlyOneRealCampaignEvenIfItIsUpcoming() {
        let up = real(2, start: 20, weeks: 8)
        XCTAssertEqual(CampaignRules.plan(start: day(25), kind: .cut, targetKg: nil, weeks: 4, existing: [dflt(1, start: 2, end: 19), up], today: day(10), calendar: cal),
                       .failure(.campaignRunning))
    }

    // MARK: labels and the dynamic period
    private func short(_ d: Date, year: Bool = false) -> String {
        var f = Date.FormatStyle(timeZone: cal.timeZone).day().month(.abbreviated)
        if year { f = f.year() }
        return d.formatted(f)
    }
    func testLabelFallsBackToTheStandardName() {
        var c = real(2, start: 2, weeks: 4)
        XCTAssertEqual(c.name, "Campaign 2 · Cut")
        c.label = "  Summer cut "
        XCTAssertEqual(c.name, "Summer cut")                      // trimmed
        c.label = "   "
        XCTAssertEqual(c.name, "Campaign 2 · Cut")                // blank = no label
        XCTAssertEqual(dflt(3, start: 2).name, "Campaign 3 · Maintenance (default)")
    }
    func testCleanLabel() {
        XCTAssertNil(CampaignRules.cleanLabel(nil)); XCTAssertNil(CampaignRules.cleanLabel("  \n "))
        XCTAssertEqual(CampaignRules.cleanLabel(" Lean bulk "), "Lean bulk")
        XCTAssertEqual(CampaignRules.cleanLabel(String(repeating: "x", count: 80))?.count, 40)
    }
    func testPlanKeepsTheLabel() {
        let plan = try! CampaignRules.plan(start: day(10), kind: .bulk, targetKg: nil, weeks: 4, existing: [dflt(1, start: 1)],
                                           label: " Lean bulk ", calendar: cal).get()
        XCTAssertEqual(plan.new.label, "Lean bulk")
        XCTAssertNil(try! CampaignRules.plan(start: day(10), kind: .bulk, targetKg: nil, weeks: 4, existing: [dflt(1, start: 1)], calendar: cal).get().new.label)
    }
    func testPeriodFollowsTheDates() {
        let running = real(1, start: 2, weeks: 4)                           // 2 Nov – 29 Nov
        XCTAssertEqual(CampaignRules.periodText(running, today: day(10), calendar: cal), "\(short(day(2))) – \(short(day(29)))")
        // Ending it early changes the period shown.
        var ended = running; ended.end = day(15); ended.endedEarly = true
        XCTAssertEqual(CampaignRules.periodText(ended, today: day(20), calendar: cal), "\(short(day(2))) – \(short(day(15)))")
        // An open-ended default has no end.
        XCTAssertEqual(CampaignRules.periodText(dflt(2, start: 5), today: day(10), calendar: cal), "since \(short(day(5)))")
    }
    func testPeriodAddsAYearOutsideTheCurrentYear() {
        let dec = cal.date(from: DateComponents(year: 2026, month: 12, day: 14))!
        let c = CampaignInfo(number: 1, kind: .cut, start: dec, plannedWeeks: 4)           // runs into January 2027
        let jan = cal.date(from: DateComponents(year: 2027, month: 1, day: 10))!
        XCTAssertEqual(CampaignRules.periodText(c, today: day(10), calendar: cal), "\(short(dec)) – \(short(jan, year: true))")
    }
    func testPickerNameAndTitleWithPeriod() {
        var c = real(2, start: 2, weeks: 4); c.label = "Summer cut"
        let period = CampaignRules.periodText(c, today: day(10), calendar: cal)
        XCTAssertEqual(CampaignRules.pickerName(c, today: day(10), calendar: cal), "#2 Summer cut · \(period)")
        XCTAssertEqual(CampaignRules.titleWithPeriod(c, today: day(10), calendar: cal), "Summer cut · \(period)")
        c.label = nil
        XCTAssertEqual(CampaignRules.pickerName(c, today: day(10), calendar: cal), "#2 Cut · \(period)")
    }
}
