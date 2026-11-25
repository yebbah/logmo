import XCTest
@testable import logmo

final class MetricsTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    /// November 2026: the 2nd is a Monday, so weeks start 2, 9, 16, 23, 30.
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }
    func snap(_ n: Int, w: Double? = nil, _ t: Set<Tracker> = [.food]) -> DaySnapshot {
        DaySnapshot(date: day(n), weightKg: w, logged: w == nil ? t : t.union([.weight]))
    }
    /// A fully logged day.
    func full(_ n: Int, kcal: Int = 2000, protein: Int = 150, water: Int = 2500, steps: Int = 9000) -> DaySnapshot {
        DaySnapshot(date: day(n), weightKg: 80, logged: Set(Tracker.allCases), complete: Set(Tracker.allCases),
                    calories: kcal, proteinG: protein, waterMl: water, steps: steps, ratings: ["sleep": 4])
    }
    let goals = GoalSet(caloriesWeekly: 14000, proteinDaily: 140, stepsDaily: 8000, waterDailyMl: 2000)
    func timeline(from n: Int = 2, _ g: GoalSet? = nil) -> GoalTimeline {
        GoalTimeline(byWeek: [day(n): g ?? goals])
    }

    // MARK: weeks
    func testWeekStartIsMonday() {
        XCTAssertEqual(Metrics.weekStart(of: day(2), calendar: cal), day(2))   // Mon
        XCTAssertEqual(Metrics.weekStart(of: day(4), calendar: cal), day(2))   // Wed
        XCTAssertEqual(Metrics.weekStart(of: day(8), calendar: cal), day(2))   // Sun
        XCTAssertEqual(Metrics.weekStart(of: day(9), calendar: cal), day(9))   // next Mon
    }

    // MARK: logging streak
    func testStreakGraceForToday() {
        let days = [snap(20), snap(21), snap(22)]
        XCTAssertEqual(Metrics.streak(days, today: day(23), calendar: cal).current, 3)
        XCTAssertEqual(Metrics.streak(days, today: day(24), calendar: cal).current, 0)
    }
    func testLongestStreak() {
        let days = [snap(1), snap(2), snap(3), snap(5), snap(6)]
        let s = Metrics.streak(days, today: day(6), calendar: cal)
        XCTAssertEqual(s.current, 2); XCTAssertEqual(s.longest, 3)
    }

    // MARK: daily goals
    func testDayGoalStatus() {
        let met = Metrics.dayGoalStatus(full(3), goals: goals)
        XCTAssertTrue(met.allMet)
        let low = Metrics.dayGoalStatus(full(3, protein: 100), goals: goals)
        XCTAssertEqual(low.protein, false); XCTAssertEqual(low.steps, true); XCTAssertFalse(low.allMet)
        XCTAssertFalse(Metrics.dayGoalStatus(nil, goals: goals).allMet)           // nothing logged = not met
        XCTAssertFalse(Metrics.dayGoalStatus(full(3), goals: nil).allMet)         // no goals = nothing to meet
        let exact = Metrics.dayGoalStatus(full(3, protein: 140), goals: goals)
        XCTAssertEqual(exact.protein, true)                                       // at the goal counts
    }
    func testPartialGoalsOnlyJudgeSetOnes() {
        let g = GoalSet(proteinDaily: 140)
        XCTAssertTrue(Metrics.dayGoalStatus(full(3, steps: 0), goals: g).allMet)
    }
    func testGoalStreak() {
        let days = [full(3), full(4), full(5, protein: 100), full(6), full(7)]
        let s = Metrics.goalStreak(days, timeline: timeline(), today: day(7), calendar: cal)
        XCTAssertEqual(s.current, 2); XCTAssertEqual(s.longest, 2)
    }
    func testGoalsInheritForwardButNotBackward() {
        let t = timeline(from: 9)
        XCTAssertNil(t.goals(forWeekStarting: day(2)))
        XCTAssertEqual(t.goals(forWeekStarting: day(16)), goals)
        XCTAssertEqual(t.inheritedFrom(day(16)), day(9))
        XCTAssertNil(t.inheritedFrom(day(9)))
    }

    // MARK: weekly calories
    func week(_ start: Int, kcal: Int) -> [DaySnapshot] { (0..<7).map { full(start + $0, kcal: kcal) } }

    func testWeekMetWhenFinishedUnderGoal() {
        let st = Metrics.weekStatus(week(2, kcal: 2000), weekStart: day(2), goals: goals, today: day(9), calendar: cal)
        XCTAssertEqual(st.total, 14000); XCTAssertEqual(st.outcome, .met)        // exactly at goal counts
    }
    func testWeekMissedWhenOver() {
        let st = Metrics.weekStatus(week(2, kcal: 2100), weekStart: day(2), goals: goals, today: day(9), calendar: cal)
        XCTAssertEqual(st.outcome, .missed)
    }
    func testFinishedWeekWithMissingDayIsNotMet() {
        var days = week(2, kcal: 1000); days.remove(at: 3)                        // far under, but a day unlogged
        let st = Metrics.weekStatus(days, weekStart: day(2), goals: goals, today: day(9), calendar: cal)
        XCTAssertEqual(st.daysWithCalories, 6); XCTAssertEqual(st.outcome, .missed)
    }
    func testWeekInProgressAndEarlyMiss() {
        let early = Metrics.weekStatus([full(2, kcal: 2000)], weekStart: day(2), goals: goals, today: day(3), calendar: cal)
        XCTAssertEqual(early.outcome, .inProgress)
        let over = Metrics.weekStatus([full(2, kcal: 15000)], weekStart: day(2), goals: goals, today: day(3), calendar: cal)
        XCTAssertEqual(over.outcome, .missed)                                     // already past the cap
        let sunday = Metrics.weekStatus(week(2, kcal: 1900), weekStart: day(2), goals: goals, today: day(8), calendar: cal)
        XCTAssertEqual(sunday.outcome, .inProgress)                               // Sunday isn't over yet
    }
    func testAtOrOverMode() {
        var g = goals; g.caloriesAtOrUnder = false
        let met = Metrics.weekStatus(week(2, kcal: 2100), weekStart: day(2), goals: g, today: day(9), calendar: cal)
        let missed = Metrics.weekStatus(week(2, kcal: 1900), weekStart: day(2), goals: g, today: day(9), calendar: cal)
        XCTAssertEqual(met.outcome, .met); XCTAssertEqual(missed.outcome, .missed)
        let mid = Metrics.weekStatus([full(2, kcal: 15000)], weekStart: day(2), goals: g, today: day(3), calendar: cal)
        XCTAssertEqual(mid.outcome, .inProgress)                                  // over is fine in this mode
    }
    func testNoCalorieGoal() {
        let st = Metrics.weekStatus(week(2, kcal: 2000), weekStart: day(2), goals: GoalSet(proteinDaily: 100), today: day(9), calendar: cal)
        XCTAssertEqual(st.outcome, .noGoal)
    }
    func testWeeklyStreak() {
        // weeks of 2, 9 and 16 met; 23 missed; 30 is in progress (today = 30)
        let days = week(2, kcal: 2000) + week(9, kcal: 1900) + week(16, kcal: 2000) + week(23, kcal: 2500) + [full(30)]
        let s = Metrics.weeklyStreak(days, timeline: timeline(), today: day(30), calendar: cal)
        XCTAssertEqual(s.current, 0); XCTAssertEqual(s.longest, 3)
        // one more good week afterwards
        let more = week(2, kcal: 2000) + week(9, kcal: 2000) + week(16, kcal: 2500) + week(23, kcal: 2000)
        let s2 = Metrics.weeklyStreak(more, timeline: timeline(), today: day(30), calendar: cal)
        XCTAssertEqual(s2.current, 1); XCTAssertEqual(s2.longest, 2)
    }
    func testWeeklyStreakNeedsGoals() {
        XCTAssertEqual(Metrics.weeklyStreak(week(2, kcal: 100), timeline: GoalTimeline(), today: day(30), calendar: cal).current, 0)
    }

    // MARK: weekly calorie average
    func testCalorieAverageComparison() {
        XCTAssertTrue(Metrics.calorieAverageOK(total: 14000, days: 7, goal: 14000, atOrUnder: true))    // 2000/day vs 2000
        XCTAssertFalse(Metrics.calorieAverageOK(total: 14007, days: 7, goal: 14000, atOrUnder: true))
        XCTAssertTrue(Metrics.calorieAverageOK(total: 4000, days: 2, goal: 14000, atOrUnder: true))     // average of days so far
        XCTAssertFalse(Metrics.calorieAverageOK(total: 4400, days: 2, goal: 14000, atOrUnder: true))    // 2200/day
        XCTAssertTrue(Metrics.calorieAverageOK(total: 4400, days: 2, goal: 14000, atOrUnder: false))
        XCTAssertFalse(Metrics.calorieAverageOK(total: 0, days: 0, goal: 14000, atOrUnder: true))       // nothing logged
    }
    func testWeekStatusExposesAverage() {
        let st = Metrics.weekStatus([full(2, kcal: 2000), full(3, kcal: 2100)], weekStart: day(2), goals: goals, today: day(3), calendar: cal)
        XCTAssertEqual(st.average!, 2050, accuracy: 1e-9)
        XCTAssertEqual(st.dailyTarget!, 2000, accuracy: 1e-9)
        XCTAssertNil(Metrics.weekStatus([], weekStart: day(2), goals: goals, today: day(3), calendar: cal).average)
    }
    func testDayNotCompliedWhenWeekAverageOverTarget() {
        let req = Set(Tracker.allCases)
        // two fully logged days, goals met, but averaging 2,200 kcal against a 2,000/day target
        let days = [full(2, kcal: 2200), full(3, kcal: 2200)]
        let c = Metrics.compliance(days, today: day(4), windowDays: 3, required: req, timeline: timeline(), calendar: cal)
        XCTAssertEqual(c.windowDays, 3)                     // the 4th is today and unlogged: counted, not complied
        XCTAssertEqual(c.compliedDays, 0)
        XCTAssertEqual(c.goalDays, 2)                       // daily goals alone were met
        // a lower-calorie day brings the average back on target: 2200 + 1800 → 2000
        let recovered = [full(2, kcal: 2200), full(3, kcal: 1800)]
        let r = Metrics.compliance(recovered, today: day(4), windowDays: 3, required: req, timeline: timeline(), calendar: cal)
        XCTAssertEqual(r.compliedDays, 2)                   // judged on the week's average, not each day
    }
    func testNoCalorieGoalMeansCaloriesDontAffectCompliance() {
        let g = GoalSet(proteinDaily: 140)
        let c = Metrics.compliance([full(2, kcal: 9000)], today: day(2), windowDays: 1, required: Set(Tracker.allCases),
                                   timeline: timeline(g), calendar: cal)
        XCTAssertEqual(c.compliedDays, 1)
    }

    // MARK: compliance
    func testComplianceNeedsLoggingAndGoals() {
        let req = Set(Tracker.allCases)
        XCTAssertTrue(Metrics.dayComplied(full(3), required: req, goals: goals))
        XCTAssertFalse(Metrics.dayComplied(full(3, steps: 100), required: req, goals: goals))   // goal missed
        var partial = full(3); partial.complete.remove(.food)
        XCTAssertFalse(Metrics.dayComplied(partial, required: req, goals: goals))               // food incomplete
        XCTAssertTrue(Metrics.dayComplied(partial, required: req.subtracting([.food]), goals: goals))  // toggle off
        XCTAssertFalse(Metrics.dayComplied(nil, required: [], goals: nil))
    }
    func testComplianceIsAlwaysOutOfTheFullWindow() {
        let days = [full(5), full(6), snap(7)]            // today (7th) only partly logged
        let c = Metrics.compliance(days, today: day(7), windowDays: 7, required: Set(Tracker.allCases),
                                   timeline: timeline(), calendar: cal)
        XCTAssertEqual(c.windowDays, 7)                   // today counts in the total, as a day not yet complied
        XCTAssertEqual(c.compliedDays, 2)
        XCTAssertEqual(c.goalDays, 2)
        let done = Metrics.compliance([full(5), full(6), full(7)], today: day(7), windowDays: 7,
                                      required: Set(Tracker.allCases), timeline: timeline(), calendar: cal)
        XCTAssertEqual(done.windowDays, 7); XCTAssertEqual(done.compliedDays, 3)
    }

    // MARK: trends
    func testTrendCarriesForwardAndFirstWeightSeeds() {
        let t = Metrics.weightTrend([snap(1, w: 80), snap(4, w: 82)], through: day(5), calendar: cal)
        XCTAssertEqual(t.count, 5)
        XCTAssertEqual(t[0].trendKg, 80); XCTAssertEqual(t[2].trendKg, 80)
        let a = Metrics.alpha(forDays: 16)
        XCTAssertEqual(t[3].trendKg, a * 82 + (1 - a) * 80, accuracy: 1e-9)
        XCTAssertNil(t[1].weightKg)
    }
    func testNoWeightsNoTrend() {
        XCTAssertTrue(Metrics.weightTrend([snap(1)], through: day(3), calendar: cal).isEmpty)
    }
    func testRatingTrend() {
        var a = snap(1); a.ratings = ["sleep": 2, "stress": 5]
        var b = snap(3); b.ratings = ["sleep": 4]
        let t = Metrics.ratingTrend([a, b], rating: "sleep", through: day(3), smoothingDays: 7, calendar: cal)
        XCTAssertEqual(t.count, 3)
        XCTAssertEqual(t[0].trend, 2); XCTAssertEqual(t[1].trend, 2)
        XCTAssertEqual(t[2].trend, 0.25 * 4 + 0.75 * 2, accuracy: 1e-9)
        XCTAssertTrue(Metrics.ratingTrend([a], rating: "hunger", through: day(3), calendar: cal).isEmpty)
    }

    // MARK: CSV
    func testCSVExportBlanksAndOrder() {
        let rows = [
            ExportRow(day: day(2), weightKg: nil, calories: 2000, proteinG: nil, fatG: nil, carbsG: 250,
                      waterMl: 0, steps: 8000, ratings: ["soreness": 4]),
            ExportRow(day: day(1), weightKg: 80.25, calories: nil, proteinG: 150, fatG: 60, carbsG: nil,
                      waterMl: nil, steps: nil, ratings: [:]),
        ]
        let lines = CSVExport.render(rows, calendar: cal).split(separator: "\n", omittingEmptySubsequences: false)
        func cells(_ l: Substring) -> [String] { l.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        XCTAssertEqual(cells(lines[0]), ["date", "weight_kg", "calories_kcal", "protein_g", "fat_g", "carbs_g", "water_ml", "steps",
                                         "sleep", "fatigue", "stress", "hunger", "performance", "appetite", "soreness"])
        XCTAssertEqual(cells(lines[1]), ["2026-11-01", "80.250", "", "150", "60", "", "", "", "", "", "", "", "", "", ""])
        XCTAssertEqual(cells(lines[2]), ["2026-11-02", "", "2000", "", "", "250", "0", "8000", "", "", "", "", "", "", "4"])
    }
}
