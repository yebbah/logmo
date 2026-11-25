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
