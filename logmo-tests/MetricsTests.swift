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
    func testADayWithoutAWeighInDoesNotMeetItsDailyGoals() {
        var s = full(3); s.weightKg = nil                        // everything else met
        let st = Metrics.dayGoalStatus(s, goals: goals)
        XCTAssertEqual(st.weight, false); XCTAssertFalse(st.allMet)
        XCTAssertNil(Metrics.dayGoalStatus(s, goals: GoalSet(caloriesWeekly: 14000)).weight)   // no daily goals: nothing to judge
        let streak = Metrics.goalStreak([full(3), s, full(5)], timeline: timeline(), today: day(5), calendar: cal)
        XCTAssertEqual(streak.current, 1)                        // the unweighed day broke it
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
    /// The real case: 1,800 a day entered as the goal (12,600 for the week), with these entries.
    func testRealEntriesAgainstADailyGoalOf1800() {
        func kcal(_ n: Int, _ v: Int) -> DaySnapshot { DaySnapshot(date: day(n), weightKg: nil, logged: [.food], calories: v) }
        let entries = [kcal(22, 1800), kcal(23, 1278), kcal(24, 1700), kcal(25, 1800)]   // 22 Nov is a Sunday: last week
        let goals = GoalSet(caloriesWeekly: 1800 * 7)
        let week = Metrics.weekStatus(entries, weekStart: day(23), goals: goals, today: day(25), calendar: cal)
        XCTAssertEqual(week.daysWithCalories, 3)
        XCTAssertEqual(week.average!, (1278.0 + 1700 + 1800) / 3, accuracy: 1e-9)       // 1,592.67
        XCTAssertEqual(week.dailyTarget!, 1800, accuracy: 1e-9)                         // not 257
        XCTAssertEqual(week.outcome, .inProgress)                                       // under target so far
        let a = Insights.averages(entries, from: day(12), to: day(25), calendar: cal)
        XCTAssertEqual(a.calories!, 1644.5, accuracy: 1e-9)                             // shown as 1,645 over the last 14 days
    }

    func testCaloriesAreAssessedOnTheWeekSoCyclingIsFine() {
        let req = Set(Tracker.allCases)            // goal: 14,000 a week = 2,000 a day on average
        func comp(_ days: [DaySnapshot], today: Int, window: Int) -> Compliance {
            Metrics.compliance(days, today: day(today), windowDays: window, required: req, timeline: timeline(), calendar: cal)
        }
        // Finished week (2–8 Nov) that cycles: Monday 2,800 and Tuesday 1,200, the rest 2,000. Average 2,000: every day complies.
        let cycling = [full(2, kcal: 2800), full(3, kcal: 1200)] + (4...8).map { full($0, kcal: 2000) }
        XCTAssertEqual(comp(cycling, today: 9, window: 8).compliedDays, 7)
        // Same week averaging 2,100: the week is over target, so no day in it complies, even the ones under 2,000.
        let over = (2...8).map { full($0, kcal: 2100) }
        let c = comp(over, today: 9, window: 8)
        XCTAssertEqual(c.compliedDays, 0)
        XCTAssertEqual(c.goalDays, 7)              // the daily goals (protein, steps, water) were all met
    }
    func testAnOpenWeekIsNotPenalisedForAHighDayYet() {
        let req = Set(Tracker.allCases)
        func comp(_ days: [DaySnapshot], today: Int) -> Compliance {
            Metrics.compliance(days, today: day(today), windowDays: 3, required: req, timeline: timeline(), calendar: cal)
        }
        // Monday 2,800 against a 2,000/day goal, Tuesday is today: the week can still average out.
        XCTAssertEqual(comp([full(2, kcal: 2800), full(3, kcal: 2000)], today: 3).compliedDays, 2)
        // But once the week's total is past 14,000 it can't come back under, so those days miss at once.
        XCTAssertEqual(comp([full(2, kcal: 15000), full(3, kcal: 2000)], today: 3).compliedDays, 0)
    }
    func testAtOrOverCaloriesAreOnlyJudgedWhenTheWeekIsFinished() {
        var g = goals; g.caloriesAtOrUnder = false
        let tl = timeline(g)
        let req = Set(Tracker.allCases)
        let low = (2...8).map { full($0, kcal: 1500) }
        XCTAssertEqual(Metrics.compliance(Array(low.prefix(2)), today: day(3), windowDays: 2, required: req, timeline: tl, calendar: cal).compliedDays, 2)
        XCTAssertEqual(Metrics.compliance(low, today: day(9), windowDays: 8, required: req, timeline: tl, calendar: cal).compliedDays, 0)
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
    func testTrendPointsCarryThePeriodFlag() {
        var a = snap(1, w: 60); a.onPeriod = true
        var b = snap(2, w: 60.2)
        b.onPeriod = false
        var c = snap(3); c.onPeriod = true                       // marked, but no weigh-in that day
        let t = Metrics.weightTrend([a, b, c], through: day(3), calendar: cal)
        XCTAssertEqual(t.map(\.onPeriod), [true, false, true])   // the trend point gets the flag even without a weigh-in
        XCTAssertNil(t[2].weightKg)
    }
    func testTrendPointsCarryTheSickFlag() {
        var a = snap(1, w: 60); a.isSick = true
        let b = snap(2, w: 60.2)
        var c = snap(3); c.isSick = true; c.onPeriod = true      // both flags can be set; no weigh-in that day
        let t = Metrics.weightTrend([a, b, c], through: day(3), calendar: cal)
        XCTAssertEqual(t.map(\.isSick), [true, false, true])
        XCTAssertEqual(t.map(\.onPeriod), [false, false, true])
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
                      waterMl: 0, steps: 8000, ratings: ["soreness": 4], performanceNA: true),
            ExportRow(day: day(1), weightKg: 80.25, calories: nil, proteinG: 150, fatG: 60, carbsG: nil,
                      waterMl: nil, steps: nil, ratings: [:], onPeriod: false),
        ]
        let lines = CSVExport.render(rows, calendar: cal).split(separator: "\n", omittingEmptySubsequences: false)
        func cells(_ l: Substring) -> [String] { l.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        XCTAssertEqual(cells(lines[0]), ["date", "weight_kg", "calories_kcal", "protein_g", "fat_g", "carbs_g", "water_ml", "steps",
                                         "sleep", "fatigue", "stress", "hunger", "performance", "appetite", "soreness", "performance_na", "on_period", "sick",
                                         "campaign_number", "campaign", "campaign_kind", "goal_calories_per_day", "goal_calories_basis", "goal_protein_g", "goal_steps", "goal_steps_basis", "goal_water_ml", "goal_workout_days", "goal_carbs_g", "goal_fat_g"])
        XCTAssertEqual(cells(lines[1]), ["2026-11-01", "80.250", "", "150", "60", "", "", "", "", "", "", "", "", "", "", "", "false", ""] + Array(repeating: "", count: 12))
        XCTAssertEqual(cells(lines[2]), ["2026-11-02", "", "2000", "", "", "250", "0", "8000", "", "", "", "", "", "", "4", "true", "", ""] + Array(repeating: "", count: 12))
    }
}
