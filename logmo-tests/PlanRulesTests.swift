import XCTest
@testable import logmo

final class PlanRulesTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    /// November 2026: Mondays are the 2nd, 9th, 16th, 23rd and 30th.
    func day(_ n: Int, month: Int = 11) -> Date { cal.date(from: DateComponents(year: 2026, month: month, day: n))! }
    func camp(start: Int, weeks: Int?, end: Int? = nil, month: Int = 11) -> CampaignInfo {
        CampaignInfo(number: 1, kind: .cut, start: day(start, month: month), plannedWeeks: weeks, end: end.map { day($0) })
    }

    // MARK: bounds
    func testBoundsForARunningCampaign() {
        let b = PlanRules.bounds(camp(start: 2, weeks: 4), today: day(10), calendar: cal)      // 2–29 Nov, today Tue 10th
        XCTAssertEqual(b.first, day(2))
        XCTAssertEqual(b.editable?.lowerBound, day(9))                                            // this week; earlier weeks are locked
        XCTAssertEqual(b.editable?.upperBound, day(23))                                           // capped by the campaign's last week
        XCTAssertEqual(b.last, day(23))
    }
    func testFourWeeksAheadForALongCampaign() {
        let b = PlanRules.bounds(camp(start: 2, weeks: 12), today: day(10), calendar: cal)
        XCTAssertEqual(b.editable?.upperBound, day(9) + 28 * 86400)                               // this week plus four
    }
    func testAnEndedCampaignIsFullyLocked() {
        let b = PlanRules.bounds(camp(start: 2, weeks: 2, end: 15), today: day(20), calendar: cal)
        XCTAssertNil(b.editable)
        XCTAssertEqual(b.last, day(9))
    }
    func testAnOpenEndedDefaultLooksFourWeeksAhead() {
        let d = CampaignInfo(number: 1, kind: .maintenance, isDefault: true, start: day(2))
        let b = PlanRules.bounds(d, today: day(10), calendar: cal)
        XCTAssertEqual(b.editable, day(9)...(day(9) + 28 * 86400))
    }
    func testAnUpcomingCampaignPlansFromItsOwnFirstWeek() {
        let c = camp(start: 14, weeks: 8, month: 12)                                              // 14 Dec, today is 25 Nov
        let b = PlanRules.bounds(c, today: day(25), calendar: cal)
        XCTAssertEqual(b.editable?.lowerBound, day(14, month: 12))
        XCTAssertEqual(b.editable?.upperBound, day(14, month: 12) + 28 * 86400)
    }

    // MARK: repeat
    func testRepeatFillsEveryFollowingWeekEvenOnesAlreadySetAndStaysInsideTheRange() {
        let b = PlanRules.bounds(camp(start: 2, weeks: 4), today: day(10), calendar: cal)         // editable 9th … 23rd
        XCTAssertEqual(PlanRules.weeksToFill(after: day(9), count: 4, bounds: b, calendar: cal), [day(16), day(23)])
        XCTAssertEqual(PlanRules.weeksToFill(after: day(9), count: 1, bounds: b, calendar: cal), [day(16)])
        XCTAssertEqual(PlanRules.followingWeeks(after: day(9), bounds: b, calendar: cal), 2)
        XCTAssertEqual(PlanRules.followingWeeks(after: day(23), bounds: b, calendar: cal), 0)
    }

    // MARK: the prompt
    func testPrompts() {
        let c = camp(start: 2, weeks: 12)
        func p(_ today: Int, any: Bool = true, explicit: Set<Date> = []) -> PlanPrompt {
            PlanRules.prompt(c, hasAnyGoals: any, explicit: explicit, today: day(today), calendar: cal)
        }
        XCTAssertEqual(p(10, any: false), .setGoals)
        XCTAssertEqual(p(11), .carriedOver(week: day(9)))                                         // Wednesday, this week not confirmed
        XCTAssertEqual(p(11, explicit: [day(9)]), .none)
        XCTAssertEqual(p(15), .planNext(week: day(16)))                                           // Sunday the 15th, next week not set
        XCTAssertEqual(p(15, explicit: [day(16)]), .none)
        XCTAssertEqual(p(15, explicit: [day(9)]), .planNext(week: day(16)))                       // this week's status doesn't matter on Sunday
        XCTAssertEqual(PlanRules.prompt(c, hasAnyGoals: true, explicit: [], today: day(1), calendar: cal), .none)   // before the campaign
    }
    func testNoPlanNextPromptBeyondTheCampaign() {
        let c = camp(start: 2, weeks: 2)                                                          // last week starts the 9th
        XCTAssertEqual(PlanRules.prompt(c, hasAnyGoals: true, explicit: [], today: day(15), calendar: cal), .none)
    }

    // MARK: week rows
    func testRowsShowGoalsComplianceAndResultsPerWeek() {
        let c = CampaignInfo(number: 1, kind: .cut, start: day(2), plannedWeeks: 2, end: day(15))
        let g = GoalSet(caloriesWeekly: 14000, proteinDaily: 140, workoutDaysWeekly: 3)
        let book = GoalRules.book(campaigns: [c], goals: [StoredGoal(campaignID: c.id, weekStart: day(2), goals: g)], calendar: cal)
        let tl = GoalTimeline(byWeek: [:], book: book)
        func snap(_ n: Int, workout: Bool, protein: Int = 150) -> DaySnapshot {
            DaySnapshot(date: day(n), weightKg: 80, logged: Set(Tracker.allCases), complete: Set(Tracker.allCases),
                        calories: 2000, proteinG: protein, waterMl: 2500, steps: 9000, ratings: workout ? ["performance": 4] : [:])
        }
        // week 1: three workouts (met); week 2: one workout (missed) and two low-protein days
        let snaps = (2...8).map { snap($0, workout: [2, 4, 6].contains($0)) }
                  + (9...15).map { snap($0, workout: $0 == 9, protein: [10, 11].contains($0) ? 100 : 150) }
        let rows = Insights.weeklyPlan(c, snaps: snaps, weeks: [day(2): g], explicit: [day(2)], timeline: tl, required: [],
                                       today: day(20), calendar: cal)
        XCTAssertEqual(rows.map(\.weekStart), [day(2), day(9)])
        XCTAssertEqual(rows.map(\.phase), [.past, .past])
        XCTAssertEqual(rows.map(\.isSet), [true, false])                                          // the second week only inherits
        XCTAssertEqual(rows[1].goals, g)                                                          // …and shows the carried-over goals
        XCTAssertNil(rows[0].previous); XCTAssertEqual(rows[1].previous, g)
        XCTAssertEqual(rows[0].days, 7); XCTAssertEqual(rows[0].compliedDays, 7)
        XCTAssertEqual(rows[1].days, 7); XCTAssertEqual(rows[1].compliedDays, 0)                  // the workout target was missed, so no day of that week complies
        XCTAssertEqual(rows[0].outcome, .met); XCTAssertNil(rows[0].reason)
        XCTAssertEqual(rows[1].outcome, .missed); XCTAssertEqual(rows[1].reason, "1 of 3 workouts")
    }
    func testWeeksKeepTheirTrendAndChange() {
        let c = camp(start: 2, weeks: 12)
        let trend = (2...16).map { TrendPoint(date: day($0), weightKg: nil, trendKg: 80 - Double($0 - 2) * 0.1) }
        let rows = Insights.weeklyPlan(c, snaps: [], weeks: [:], explicit: [], timeline: GoalTimeline(), required: [],
                                       today: day(16), trend: trend, calendar: cal)
        XCTAssertNil(rows[0].trendChangeKg)                                    // nothing before the first week
        XCTAssertNotNil(rows[0].trendKg)
        XCTAssertEqual(rows[1].trendChangeKg ?? 0, -0.7, accuracy: 0.01)
        XCTAssertNil(rows.last(where: { $0.phase == .future })?.trendKg)       // future weeks have none
    }
    func testAFutureWeekHasGoalsButNoDays() {
        let c = camp(start: 2, weeks: 12)
        let g = GoalSet(caloriesWeekly: 14000)
        let rows = Insights.weeklyPlan(c, snaps: [], weeks: [day(2): g], explicit: [day(2)],
                                       timeline: GoalTimeline(), required: [], today: day(10), calendar: cal)
        let next = rows.first { $0.weekStart == day(16) }!
        XCTAssertEqual(next.phase, .future); XCTAssertEqual(next.days, 0)
        XCTAssertEqual(next.goals, g); XCTAssertFalse(next.isSet)
        XCTAssertEqual(next.outcome, .inProgress)
        XCTAssertEqual(rows.first { $0.weekStart == day(9) }!.phase, .current)
    }
    func testTheFirstWeekOfAMidWeekCampaignCountsOnlyItsOwnDays() {
        let c = CampaignInfo(number: 2, kind: .cut, start: day(4), plannedWeeks: 4, end: day(30))   // starts on a Wednesday
        let rows = Insights.weeklyPlan(c, snaps: [], weeks: [:], explicit: [], timeline: GoalTimeline(), required: [], today: day(20), calendar: cal)
        XCTAssertEqual(rows.first!.weekStart, day(2))
        XCTAssertEqual(rows.first!.days, 5)                                                       // Wed to Sun
    }

    func testOnlyTheDaysThatMissedTheirDailyGoalAreRedInAMetWeek() {
        let c = CampaignInfo(number: 1, kind: .cut, start: day(2), plannedWeeks: 1, end: day(8))
        let g = GoalSet(proteinDaily: 140)
        let book = GoalRules.book(campaigns: [c], goals: [StoredGoal(campaignID: c.id, weekStart: day(2), goals: g)], calendar: cal)
        let snaps = (2...8).map { n in
            DaySnapshot(date: day(n), weightKg: 80, logged: Set(Tracker.allCases), complete: Set(Tracker.allCases),
                        calories: 2000, proteinG: n == 4 ? 100 : 150, waterMl: 2500, steps: 9000)
        }
        let rows = Insights.weeklyPlan(c, snaps: snaps, weeks: [day(2): g], explicit: [day(2)],
                                       timeline: GoalTimeline(byWeek: [:], book: book), required: [], today: day(20), calendar: cal)
        XCTAssertEqual(rows[0].compliedDays, 6)
        XCTAssertEqual(rows[0].strip[2], .missed)                                                 // Wednesday the 4th
        XCTAssertEqual(rows[0].outcome, .noGoal)                                                  // a protein-only plan has no weekly goal
    }
}
