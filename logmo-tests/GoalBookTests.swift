import XCTest
@testable import logmo

final class GoalBookTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }   // 2 Nov 2026 is a Monday

    func camps() -> (CampaignInfo, CampaignInfo) {
        // A: 2 Nov – 11 Nov (Mon – Wed of week 2), B: from 12 Nov (Thu)
        let a = CampaignInfo(number: 1, kind: .maintenance, isDefault: true, start: day(2), end: day(11))
        let b = CampaignInfo(number: 2, kind: .cut, start: day(12), plannedWeeks: 8)
        return (a, b)
    }
    func g(_ protein: Int, kcal: Int = 14000) -> GoalSet { GoalSet(caloriesWeekly: kcal, proteinDaily: protein) }

    func testEachDayUsesItsOwnCampaignsGoals() {
        let (a, b) = camps()
        let stored = [StoredGoal(campaignID: a.id, weekStart: day(2), goals: g(100)),
                      StoredGoal(campaignID: b.id, weekStart: day(9), goals: g(160))]
        let book = GoalRules.book(campaigns: [a, b], goals: stored, calendar: cal)
        XCTAssertEqual(book.goals(forDay: day(3), calendar: cal)?.proteinDaily, 100)     // campaign A
        XCTAssertEqual(book.goals(forDay: day(11), calendar: cal)?.proteinDaily, 100)    // A's last day
        XCTAssertEqual(book.goals(forDay: day(12), calendar: cal)?.proteinDaily, 160)    // B's first day, same week
        XCTAssertEqual(book.goals(forDay: day(20), calendar: cal)?.proteinDaily, 160)    // inherited within B
    }
    func testGoalsDoNotLeakAcrossCampaigns() {
        let (a, b) = camps()
        let book = GoalRules.book(campaigns: [a, b], goals: [StoredGoal(campaignID: a.id, weekStart: day(2), goals: g(100))], calendar: cal)
        XCTAssertNil(book.goals(forDay: day(12), calendar: cal))       // B has none of its own
        XCTAssertNil(book.goals(forDay: day(1), calendar: cal))        // before any campaign
    }
    func testWeekBelongsToTheCampaignContainingItsMonday() {
        let (a, b) = camps()
        let stored = [StoredGoal(campaignID: a.id, weekStart: day(9), goals: g(100, kcal: 14000)),
                      StoredGoal(campaignID: b.id, weekStart: day(9), goals: g(160, kcal: 17500))]
        let book = GoalRules.book(campaigns: [a, b], goals: stored, calendar: cal)
        XCTAssertEqual(book.goals(forWeekStarting: day(9), calendar: cal)?.caloriesWeekly, 14000)   // Monday 9 Nov is in A
        XCTAssertEqual(book.goals(forWeekStarting: day(16), calendar: cal)?.caloriesWeekly, 17500)  // Monday 16 Nov is in B
    }
    func testOrphanGoalsGoToTheCampaignContainingTheirWeek() {
        let (a, b) = camps()
        let book = GoalRules.book(campaigns: [a, b], goals: [StoredGoal(campaignID: nil, weekStart: day(16), goals: g(150))], calendar: cal)
        XCTAssertEqual(book.byCampaign[b.id]?[day(16)]?.proteinDaily, 150)
        let early = GoalRules.book(campaigns: [a, b], goals: [StoredGoal(campaignID: nil, weekStart: day(2) - 86400 * 14, goals: g(90))], calendar: cal)
        XCTAssertNotNil(early.byCampaign[a.id])                          // before everything: earliest campaign
    }

    // MARK: seeding a new campaign
    func testNewCampaignStartsWithTheLatestGoals() {
        let (a, b) = camps()
        let existing = [StoredGoal(campaignID: a.id, weekStart: day(2), goals: g(100)),
                        StoredGoal(campaignID: a.id, weekStart: day(9), goals: g(120))]
        let seed = GoalRules.seed(for: b, from: existing, calendar: cal)!
        XCTAssertEqual(seed.goals.proteinDaily, 120)                     // the most recent, not the first
        XCTAssertEqual(seed.weekStart, day(9))                           // Monday of the week B starts (Thu 12 Nov)
    }
    func testNoSeedWithoutAnyGoals() {
        let (_, b) = camps()
        XCTAssertNil(GoalRules.seed(for: b, from: [], calendar: cal))
        XCTAssertNil(GoalRules.seed(for: b, from: [StoredGoal(campaignID: b.id, weekStart: day(9), goals: g(1))], calendar: cal))  // its own don't count
    }

    // MARK: metrics follow each day's campaign
    func testComplianceUsesTheDaysOwnCampaignGoals() {
        let (a, b) = camps()
        let stored = [StoredGoal(campaignID: a.id, weekStart: day(2), goals: GoalSet(proteinDaily: 100)),
                      StoredGoal(campaignID: b.id, weekStart: day(9), goals: GoalSet(proteinDaily: 160))]
        let tl = GoalTimeline(byWeek: [:], book: GoalRules.book(campaigns: [a, b], goals: stored, calendar: cal))
        func full(_ n: Int, protein: Int) -> DaySnapshot {
            DaySnapshot(date: day(n), weightKg: 80, logged: Set(Tracker.allCases), complete: Set(Tracker.allCases),
                        calories: 2000, proteinG: protein, waterMl: 2500, steps: 9000, ratings: [:])
        }
        let days = [full(10, protein: 120), full(11, protein: 120), full(12, protein: 120), full(13, protein: 170)]
        let streak = Metrics.goalStreak(days, timeline: tl, today: day(13), calendar: cal)
        XCTAssertEqual(streak.longest, 2)           // 10th and 11th meet A's 100 g; the 12th misses B's 160 g
        XCTAssertEqual(streak.current, 1)           // the 13th meets B's goal
        let p = Insights.proteinDays(days, timeline: tl, from: day(10), to: day(13), calendar: cal)
        XCTAssertEqual(p.hit, 3); XCTAssertEqual(p.missed, 1)
    }
}
