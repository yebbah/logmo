import XCTest
@testable import logmo

final class CampaignReportTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }   // Mon 2 Nov 2026

    /// A two-week cut, 2–15 Nov: weight falls 0.1 kg a day, goals met every day, three workouts a week.
    func scenario() -> (CampaignInfo, [DaySnapshot], GoalTimeline) {
        let c = CampaignInfo(number: 1, kind: .cut, start: day(2), plannedWeeks: 2, end: day(15))
        let goals = GoalSet(caloriesWeekly: 14000, proteinDaily: 140, workoutDaysWeekly: 3)
        let book = GoalRules.book(campaigns: [c], goals: [StoredGoal(campaignID: c.id, weekStart: day(2), goals: goals)], calendar: cal)
        let workouts: Set<Int> = [2, 4, 6, 9, 11, 13]
        let snaps = (2...15).map { n -> DaySnapshot in
            var r = ["sleep": 4]
            if workouts.contains(n) { r["performance"] = 4 }
            return DaySnapshot(date: day(n), weightKg: 80 - 0.1 * Double(n - 2), logged: Set(Tracker.allCases),
                               complete: Set(Tracker.allCases), calories: 2000, proteinG: 150, carbsG: 200, fatG: 60,
                               waterMl: 2500, steps: 9000, ratings: r)
        }
        return (c, snaps, GoalTimeline(byWeek: [:], book: book))
    }

    func testAFinishedCampaignsReport() {
        let (c, snaps, tl) = scenario()
        let trend = Metrics.weightTrend(snaps, through: day(20), smoothingDays: 1, calendar: cal)   // alpha 1: trend = weight
        let r = Insights.campaignReport(c, snaps: snaps, trend: trend, timeline: tl, required: [], today: day(20), calendar: cal)
        XCTAssertEqual(r.days, 14); XCTAssertEqual(r.daysLogged, 14); XCTAssertEqual(r.daysWeighed, 14)
        XCTAssertEqual(r.startTrendKg!, 80, accuracy: 1e-9); XCTAssertEqual(r.endTrendKg!, 78.7, accuracy: 1e-9)
        XCTAssertEqual(r.changeKg!, -1.3, accuracy: 1e-9)
        XCTAssertEqual(r.avgWeeklyChangeKg!, -0.7, accuracy: 1e-9)             // -1.3 over 13 days, per week
        XCTAssertEqual(r.fastestWeekKg!, -0.7, accuracy: 1e-9)
        XCTAssertEqual(r.compliance.windowDays, 14); XCTAssertEqual(r.compliance.compliedDays, 14)
        XCTAssertEqual(r.dailyGoalDays, 14); XCTAssertEqual(r.dailyGoalDaysMet, 14)
        XCTAssertEqual(r.weeklyGoals, 2); XCTAssertEqual(r.weeklyGoalsMet, 2)     // 2000/day and 3 workouts, both weeks
        XCTAssertEqual(r.workoutsPerWeek!, 3, accuracy: 1e-9)
        XCTAssertEqual(r.averages.calories!, 2000); XCTAssertEqual(r.averages.carbsG!, 200)
        XCTAssertEqual(r.averages.fatG!, 60); XCTAssertEqual(r.averages.waterMl!, 2500); XCTAssertEqual(r.averages.steps!, 9000)
        XCTAssertEqual(r.ratingAverages["sleep"]!, 4, accuracy: 1e-9)
        XCTAssertEqual(r.ratingAverages["performance"]!, 4, accuracy: 1e-9)
        XCTAssertNil(r.ratingAverages["stress"])                                 // never logged: no average, not 0
        XCTAssertEqual(r.goalsAtEnd?.proteinDaily, 140)
    }

    func testOnlyTheCampaignsOwnDaysCount() {
        let (c, snaps, tl) = scenario()
        let outside = snaps + [DaySnapshot(date: day(20), weightKg: 99, logged: [.food], calories: 9999)]
        let trend = Metrics.weightTrend(outside, through: day(20), smoothingDays: 1, calendar: cal)
        let r = Insights.campaignReport(c, snaps: outside, trend: trend, timeline: tl, required: [], today: day(20), calendar: cal)
        XCTAssertEqual(r.averages.calories!, 2000)                               // the 20th is after the campaign ended
        XCTAssertEqual(r.endTrendKg!, 78.7, accuracy: 1e-9)
        XCTAssertEqual(r.days, 14)
    }

    func testARunningCampaignIsJudgedSoFarAndAnUpcomingOneHasNothing() {
        let (_, snaps, tl) = scenario()
        var running = CampaignInfo(number: 1, kind: .cut, start: day(2), plannedWeeks: 2)      // still open
        running.end = nil
        let trend = Metrics.weightTrend(snaps, through: day(8), smoothingDays: 1, calendar: cal)
        let r = Insights.campaignReport(running, snaps: snaps, trend: trend, timeline: tl, required: [], today: day(8), calendar: cal)
        XCTAssertEqual(r.days, 7)                                                // 2–8 Nov: to today, not to the planned end
        XCTAssertEqual(r.endTrendKg!, 79.4, accuracy: 1e-9)

        let upcoming = CampaignInfo(number: 2, kind: .bulk, start: day(30), plannedWeeks: 4)
        let u = Insights.campaignReport(upcoming, snaps: snaps, trend: trend, timeline: tl, required: [], today: day(8), calendar: cal)
        XCTAssertFalse(u.started); XCTAssertEqual(u.days, 0)
        XCTAssertNil(u.changeKg); XCTAssertEqual(u.compliance.windowDays, 0)
    }

    func testNoWeighInsMeansNoWeightResult() {
        let (c, snaps, tl) = scenario()
        let unweighed = snaps.map { s -> DaySnapshot in var x = s; x.weightKg = nil; return x }
        let trend = Metrics.weightTrend(unweighed, through: day(20), smoothingDays: 1, calendar: cal)
        let r = Insights.campaignReport(c, snaps: unweighed, trend: trend, timeline: tl, required: [], today: day(20), calendar: cal)
        XCTAssertNil(r.changeKg); XCTAssertNil(r.avgWeeklyChangeKg); XCTAssertNil(r.fastestWeekKg)
        XCTAssertEqual(r.daysWeighed, 0)
    }

    func testComplianceOverARangeMatchesTheWindowVersion() {
        let (_, snaps, tl) = scenario()
        let a = Metrics.compliance(snaps, today: day(15), windowDays: 7, required: [], timeline: tl, calendar: cal)
        let b = Metrics.compliance(snaps, from: day(9), to: day(15), today: day(15), required: [], timeline: tl, calendar: cal)
        XCTAssertEqual(a, b)
    }
}

final class ComplianceStripTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }
    func full(_ n: Int, protein: Int = 150) -> DaySnapshot {
        DaySnapshot(date: day(n), weightKg: 80, logged: Set(Tracker.allCases), complete: Set(Tracker.allCases),
                    calories: 2000, proteinG: protein, waterMl: 2500, steps: 9000)
    }
    func testStripHasOneEntryPerDayAndTodayStaysOpen() {
        let tl = GoalTimeline(byWeek: [day(2): GoalSet(proteinDaily: 140)])
        let days = [full(2), full(3, protein: 100), full(4)]                         // 4th is today and complete
        let strip = Metrics.complianceStrip(days, from: day(2), to: day(5), today: day(5), required: Set(Tracker.allCases), timeline: tl, calendar: cal)
        XCTAssertEqual(strip, [.complied, .missed, .complied, .open])                // the 5th is today, nothing logged yet
        let c = Metrics.compliance(days, from: day(2), to: day(5), today: day(5), required: Set(Tracker.allCases), timeline: tl, calendar: cal)
        XCTAssertEqual(strip.filter { $0 == .complied }.count, c.compliedDays)       // the strip and the count agree
    }
}
