import XCTest
import SwiftData
@testable import logmo

@MainActor
final class CampaignChangeTests: XCTestCase {
    let cal = Calendar.current
    var today: Date { cal.startOfDay(for: Date()) }
    func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }     // day(0) = today

    /// nil on success, else the error (Result<Void, _> isn't Equatable).
    func err(_ r: Result<Void, CampaignError>) -> CampaignError? { if case .failure(let e) = r { return e }; return nil }

    var container: ModelContainer?                  // kept alive for the test: a context doesn't own its container

    func makeContext() throws -> ModelContext {
        let c = try ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container = c
        return c.mainContext
    }

    /// A running 4-week campaign that started 21 days ago: it ends in 7 days (day(6) is its last day).
    func running(_ context: ModelContext, weeks: Int = 4) -> Campaign {
        let c = Campaign(CampaignInfo(number: 1, kind: .cut, start: day(-21), plannedWeeks: weeks))
        context.insert(c); try? context.save(); return c
    }

    func testClosingInOnlyInTheLastWeek() {
        let c = CampaignInfo(number: 1, kind: .cut, start: day(-21), plannedWeeks: 4)      // 7 days left, counting today
        XCTAssertEqual(CampaignRules.closingIn(c, today: today), 7)
        XCTAssertNil(CampaignRules.closingIn(CampaignInfo(number: 1, kind: .cut, start: day(-20), plannedWeeks: 4), today: today))   // 8 left
        XCTAssertNil(CampaignRules.closingIn(CampaignInfo(number: 1, kind: .cut, start: day(-28), plannedWeeks: 4), today: today))   // finished
        XCTAssertNil(CampaignRules.closingIn(CampaignInfo(number: 2, kind: .maintenance, isDefault: true, start: day(-30)), today: today))
    }

    func testQueueACampaignAfterTheRunningOne_withMaintenanceBetween() throws {
        let context = try makeContext(); let r = running(context)
        // The running one's last day is day(6). Start the next on day(10): days 7-9 are maintenance.
        XCTAssertNil(err(CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(10), weeks: 4)))
        let all = CampaignStore.all(context)
        XCTAssertEqual(all.map(\.number), [1, 2, 3])
        XCTAssertTrue(all[1].isDefault); XCTAssertEqual(all[1].start, day(7)); XCTAssertEqual(all[1].end, day(9))
        XCTAssertEqual(all[2].start, day(10)); XCTAssertNil(r.end)
        // Every day from the running campaign's start to the end of the queued one belongs to exactly one campaign.
        for n in -21...37 { XCTAssertEqual(CampaignRules.campaign(for: day(n), in: all.map(\.info))?.number,
                                           n <= 6 ? 1 : (n <= 9 ? 2 : 3), "day \(n)") }
    }

    func testQueueingBeforeTheRunningCampaignsEndIsRefused() throws {
        let context = try makeContext(); _ = running(context)
        XCTAssertEqual(err(CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(3), weeks: 4)), .startsBeforeCurrent)
    }

    func testMovingTheUpcomingStartRefillsTheGap() throws {
        let context = try makeContext(); _ = running(context)
        CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(10), weeks: 4)
        let u = CampaignStore.upcoming(context)!
        XCTAssertNil(err(CampaignStore.reschedule(context, u, start: day(14), weeks: 6)))
        var all = CampaignStore.all(context)
        XCTAssertEqual(all.map(\.number), [1, 2, 3])
        XCTAssertEqual(all[1].start, day(7)); XCTAssertEqual(all[1].end, day(13))
        XCTAssertEqual(all[2].start, day(14)); XCTAssertEqual(all[2].plannedWeeks, 6)
        // Back to the very next day: the gap, and its maintenance campaign, disappear.
        XCTAssertNil(err(CampaignStore.reschedule(context, CampaignStore.upcoming(context)!, start: day(7), weeks: 6)))
        all = CampaignStore.all(context)
        XCTAssertEqual(all.map(\.number), [1, 2]); XCTAssertEqual(all[1].start, day(7)); XCTAssertFalse(all[1].isDefault)
    }

    func testUpcomingCannotStartBeforeTheRunningCampaignEnds() throws {
        let context = try makeContext(); _ = running(context)
        CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(10), weeks: 4)
        XCTAssertEqual(err(CampaignStore.reschedule(context, CampaignStore.upcoming(context)!, start: day(6), weeks: 4)), .startsBeforeCurrent)
    }

    func testRescheduleWithNothingRunningMovesTheDefaultsEnd() throws {
        let context = try makeContext()
        CampaignStore.ensureDefault(context)
        CampaignStore.start(context, kind: .cut, targetKg: nil, start: day(5), weeks: 3)
        let u = CampaignStore.upcoming(context)!
        XCTAssertNil(err(CampaignStore.reschedule(context, u, start: day(9), weeks: 2)))
        let d = CampaignStore.all(context).first { $0.isDefault }!
        XCTAssertEqual(d.end, day(8))
        XCTAssertEqual(CampaignRules.campaign(for: day(8), in: CampaignStore.all(context).map(\.info))?.isDefault, true)
    }

    func testExtendingIsRefusedWhenItWouldHitTheNextCampaign_andShrinksTheGapOtherwise() throws {
        let context = try makeContext(); let r = running(context)
        CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(17), weeks: 4)       // gap: days 7-16
        XCTAssertFalse(CampaignStore.extend(context, r, byWeeks: 2))                              // would end on day 20
        XCTAssertTrue(CampaignStore.extend(context, r, byWeeks: 1))                               // ends day 13: gap is days 14-16
        let filler = CampaignStore.all(context).first { $0.isDefault }!
        XCTAssertEqual(filler.start, day(14)); XCTAssertEqual(filler.end, day(16))
        XCTAssertTrue(CampaignStore.extend(context, r, byWeeks: 0) == false)
    }

    func testRunningCampaignClosesItselfWhenItsPlannedDaysPassAndAnotherIsQueued() throws {
        let context = try makeContext()
        let r = Campaign(CampaignInfo(number: 1, kind: .cut, start: day(-30), plannedWeeks: 2))   // planned end was day(-17)
        context.insert(r)
        context.insert(Campaign(CampaignInfo(number: 2, kind: .bulk, start: day(-10), plannedWeeks: 4)))
        CampaignStore.settle(context, today: today)
        XCTAssertEqual(r.end, day(-17)); XCTAssertFalse(r.endedEarly)
    }

    func testEndingEarlyWithANextCampaignQueued_keepsEveryDayCovered() throws {
        let context = try makeContext(); let r = running(context)
        CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(10), weeks: 4)
        CampaignStore.end(context, r)                                        // ends today
        let infos = CampaignStore.all(context).map(\.info)
        for n in -21...37 { XCTAssertNotNil(CampaignRules.campaign(for: day(n), in: infos), "day \(n)") }
        XCTAssertEqual(CampaignRules.campaign(for: day(5), in: infos)?.isDefault, true)
    }

    func testCancellingAQueuedCampaignLeavesTheRunningOneAndNoMaintenance() throws {
        let context = try makeContext(); let r = running(context)
        CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(10), weeks: 4)
        CampaignStore.cancelUpcoming(context, CampaignStore.upcoming(context)!)
        XCTAssertEqual(CampaignStore.all(context).map(\.id), [r.id]); XCTAssertNil(r.end)
    }

    func testPastCampaignsCannotBeEdited() throws {
        let context = try makeContext()
        let p = Campaign(CampaignInfo(number: 1, kind: .cut, start: day(-40), plannedWeeks: 4, end: day(-13), label: "Summer"))
        context.insert(p)
        CampaignStore.rename(context, p, to: "Changed")
        XCTAssertEqual(p.label, "Summer")
        XCTAssertEqual(err(CampaignStore.reschedule(context, p, start: day(30), weeks: 3)), .notEditable)
        XCTAssertFalse(CampaignStore.extend(context, p, byWeeks: 2))
        // a running campaign can't be rescheduled either: only one that hasn't started
        let r = running(context)
        XCTAssertEqual(err(CampaignStore.reschedule(context, r, start: day(30), weeks: 3)), .notEditable)
    }
}
