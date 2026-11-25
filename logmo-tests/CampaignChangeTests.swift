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

    func testQueueACampaignAfterTheRunningOne_nothingFillsTheGap() throws {
        let context = try makeContext(); let r = running(context)
        // The running one's last day is day(6). Start the next on day(10): days 7 to 9 belong to no campaign.
        XCTAssertNil(err(CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(10), weeks: 4, startWeightKg: 80)))
        let all = CampaignStore.all(context)
        XCTAssertEqual(all.map(\.number), [1, 2]); XCTAssertTrue(all.allSatisfy { !$0.isDefault })        // nothing automatic was created
        XCTAssertNil(r.end)
        for n in -21...37 {
            let expected: Int? = n <= 6 ? 1 : (n >= 10 ? 2 : nil)
            XCTAssertEqual(CampaignRules.campaign(for: day(n), in: all.map(\.info))?.number, expected, "day \(n)")
        }
    }

    func testQueueingBeforeTheRunningCampaignsEndIsRefused() throws {
        let context = try makeContext(); _ = running(context)
        XCTAssertEqual(err(CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(3), weeks: 4, startWeightKg: 80)), .startsBeforeCurrent)
    }

    func testMovingTheUpcomingStartJustMovesIt() throws {
        let context = try makeContext(); _ = running(context)
        CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(10), weeks: 4, startWeightKg: 80)
        let u = CampaignStore.upcoming(context)!
        XCTAssertNil(err(CampaignStore.reschedule(context, u, start: day(14), weeks: 6)))
        let all = CampaignStore.all(context)
        XCTAssertEqual(all.map(\.number), [1, 2]); XCTAssertEqual(all[1].start, day(14)); XCTAssertEqual(all[1].plannedWeeks, 6)
        XCTAssertNil(err(CampaignStore.reschedule(context, CampaignStore.upcoming(context)!, start: day(7), weeks: 6)))     // the very next day is allowed
        XCTAssertEqual(CampaignStore.all(context)[1].start, day(7))
    }

    func testUpcomingCannotStartBeforeTheRunningCampaignEnds() throws {
        let context = try makeContext(); _ = running(context)
        CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(10), weeks: 4, startWeightKg: 80)
        XCTAssertEqual(err(CampaignStore.reschedule(context, CampaignStore.upcoming(context)!, start: day(6), weeks: 4)), .startsBeforeCurrent)
    }

    func testStartingTheFirstCampaignOnAnEmptyStoreCreatesOnlyThatCampaign() throws {
        let context = try makeContext()
        CampaignStore.tidy(context)
        XCTAssertTrue(CampaignStore.all(context).isEmpty)                                    // nothing is made automatically
        XCTAssertNil(err(CampaignStore.start(context, kind: .maintenance, targetKg: nil, start: today, weeks: 8, startWeightKg: 70)))
        let all = CampaignStore.all(context)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(CampaignRules.lastDay(all[0].info), day(55))                          // an explicit end: 8 weeks from today
    }

    func testAnOldAutomaticCampaignLeftOpenIsClosedSoNothingIsOpenEnded() throws {
        let context = try makeContext()
        context.insert(Campaign(CampaignInfo(number: 1, kind: .maintenance, isDefault: true, start: day(-60))))               // an older version's open default
        context.insert(Campaign(CampaignInfo(number: 2, kind: .maintenance, isDefault: true, start: day(0))))                 // began today, no days yet
        try context.save()
        CampaignStore.tidy(context)
        let all = CampaignStore.all(context)
        XCTAssertEqual(all.map(\.number), [1])                                               // the empty one is removed
        XCTAssertEqual(all[0].end, day(-1))                                                  // the other ends yesterday, its days stay as history
        XCTAssertTrue(all.allSatisfy { $0.end != nil })
        CampaignStore.tidy(context)                                                          // and tidying again changes nothing
        XCTAssertEqual(CampaignStore.all(context).count, 1)
    }

    func testExtendingIsRefusedWhenItWouldHitTheNextCampaign_andAllowedUpToIt() throws {
        let context = try makeContext(); let r = running(context)
        CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(17), weeks: 4, startWeightKg: 80)       // runs 17 and on
        XCTAssertFalse(CampaignStore.extend(context, r, byWeeks: 2))                                                 // would end on day 20
        XCTAssertTrue(CampaignStore.extend(context, r, byWeeks: 1))                                                  // ends day 13
        XCTAssertEqual(CampaignRules.lastDay(r.info), day(13))
        XCTAssertFalse(CampaignStore.extend(context, r, byWeeks: 0))
    }

    func testRunningCampaignClosesItselfWhenItsPlannedDaysPassAndAnotherIsQueued() throws {
        let context = try makeContext()
        let r = Campaign(CampaignInfo(number: 1, kind: .cut, start: day(-30), plannedWeeks: 2))   // planned end was day(-17)
        context.insert(r)
        context.insert(Campaign(CampaignInfo(number: 2, kind: .bulk, start: day(-10), plannedWeeks: 4)))
        CampaignStore.settle(context, today: today)
        XCTAssertEqual(r.end, day(-17)); XCTAssertFalse(r.endedEarly)
    }

    func testEndingEarlyLeavesTheDaysAfterWithoutACampaign() throws {
        let context = try makeContext(); let r = running(context)
        CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(10), weeks: 4, startWeightKg: 80)
        CampaignStore.end(context, r)                                                        // ends today
        let infos = CampaignStore.all(context).map(\.info)
        XCTAssertEqual(infos.count, 2)                                                       // nothing automatic was added
        XCTAssertNotNil(CampaignRules.campaign(for: day(0), in: infos)); XCTAssertEqual(CampaignRules.lastDay(infos[0]), day(0))
        XCTAssertNil(CampaignRules.campaign(for: day(5), in: infos))
        XCTAssertEqual(CampaignRules.campaign(for: day(10), in: infos)?.number, 2)
    }

    func testCancellingAQueuedCampaignLeavesTheRunningOne() throws {
        let context = try makeContext(); let r = running(context)
        CampaignStore.start(context, kind: .bulk, targetKg: nil, start: day(10), weeks: 4, startWeightKg: 80)
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
        let r = running(context)                                                              // a running campaign can't be rescheduled either: only one that hasn't started
        XCTAssertEqual(err(CampaignStore.reschedule(context, r, start: day(30), weeks: 3)), .notEditable)
    }
}

final class DaysLeftBadgeTests: XCTestCase {
    let cal = Calendar.current
    var today: Date { cal.startOfDay(for: Date()) }
    func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }

    func testTheBadgeCountsDaysLeftIncludingToday() {
        let c = CampaignInfo(number: 2, kind: .cut, start: day(-20), plannedWeeks: 4)            // last planned day is day(7)
        XCTAssertEqual(CampaignRules.daysLeftBadge([c], today: today), "8 days left")
        let last = CampaignInfo(number: 2, kind: .cut, start: day(-27), plannedWeeks: 4)
        XCTAssertEqual(CampaignRules.daysLeftBadge([last], today: today), "1 day left")
    }

    func testNoBadgeWithoutARunningRealCampaign() {
        let auto = CampaignInfo(number: 1, kind: .maintenance, isDefault: true, start: day(-90))
        XCTAssertNil(CampaignRules.daysLeftBadge([auto], today: today))
        let upcoming = CampaignInfo(number: 2, kind: .cut, start: day(5), plannedWeeks: 4)
        XCTAssertNil(CampaignRules.daysLeftBadge([auto, upcoming], today: today))
        let ended = CampaignInfo(number: 2, kind: .cut, start: day(-40), plannedWeeks: 4, end: day(-12))
        XCTAssertNil(CampaignRules.daysLeftBadge([auto, ended], today: today))
    }

    func testACampaignPastItsPlannedEndShowsNoBadge() {
        let over = CampaignInfo(number: 2, kind: .cut, start: day(-40), plannedWeeks: 4)         // its days ended on day(-13); it no longer covers today
        XCTAssertNil(CampaignRules.daysLeftBadge([over], today: today))
    }
}
