import XCTest
@testable import logmo

final class WorkoutTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }   // Mon 2 Nov … Sun 8 Nov

    /// A day with a workout (training performance 1–5), a rest day (n/a), or nothing answered.
    func workout(_ n: Int) -> DaySnapshot {
        DaySnapshot(date: day(n), weightKg: nil, logged: [.checkIn], ratings: ["performance": 4])
    }
    func rest(_ n: Int) -> DaySnapshot {
        DaySnapshot(date: day(n), weightKg: nil, logged: [.checkIn], performanceNA: true)
    }
    func steps(_ n: Int, _ v: Int) -> DaySnapshot {
        DaySnapshot(date: day(n), weightKg: nil, logged: [.steps], steps: v)
    }
    let goals4 = GoalSet(workoutDaysWeekly: 4)

    // MARK: workout days
    func testWorkoutsCountOnlyRatedDays() {
        let days = [workout(2), rest(3), workout(4), DaySnapshot(date: day(5), weightKg: nil, logged: [.food])]
        let w = Metrics.workoutWeek(days, weekStart: day(2), goals: goals4, today: day(6), calendar: cal)
        XCTAssertEqual(w.done, 2)                       // n/a and unrated days are not workouts
        XCTAssertEqual(w.outcome, .inProgress)
    }
    func testWorkoutGoalMetWhenReachedEvenMidWeek() {
        let days = [workout(2), workout(3), workout(4), workout(5)]
        XCTAssertEqual(Metrics.workoutWeek(days, weekStart: day(2), goals: goals4, today: day(5), calendar: cal).outcome, .met)
    }
    func testWorkoutMissedOnceTheTargetIsOutOfReach() {
        // Thursday 5 Nov, one workout so far and rest days on Mon–Wed: open days left = Thu, Fri, Sat, Sun = 4 → 1 + 4 ≥ 4
        let days = [workout(2), rest(3), rest(4)]
        XCTAssertEqual(Metrics.workoutWeek(days, weekStart: day(2), goals: goals4, today: day(5), calendar: cal).outcome, .inProgress)
        // Saturday: open = Sat, Sun = 2 → 1 + 2 < 4
        XCTAssertEqual(Metrics.workoutWeek(days + [rest(5), rest(6), rest(7)].dropLast(), weekStart: day(2), goals: goals4, today: day(7), calendar: cal).outcome, .missed)
    }
    func testNaDayIsNotOpenForAWorkout() {
        // Sunday 8th is the last day. Today is Sunday, already answered n/a → nothing left to log.
        let days = [workout(2), workout(3), workout(4), rest(8)]
        let w = Metrics.workoutWeek(days, weekStart: day(2), goals: goals4, today: day(8), calendar: cal)
        XCTAssertEqual(w.possible, 3); XCTAssertEqual(w.outcome, .missed)
        // Same, but today is still unanswered: one workout day could still happen
        let w2 = Metrics.workoutWeek([workout(2), workout(3), workout(4)], weekStart: day(2), goals: goals4, today: day(8), calendar: cal)
        XCTAssertEqual(w2.possible, 4); XCTAssertEqual(w2.outcome, .inProgress)
    }
    func testFinishedWeekIsMetOrMissed() {
        let met = [workout(2), workout(3), workout(5), workout(7)]
        XCTAssertEqual(Metrics.workoutWeek(met, weekStart: day(2), goals: goals4, today: day(9), calendar: cal).outcome, .met)
        XCTAssertEqual(Metrics.workoutWeek([workout(2)], weekStart: day(2), goals: goals4, today: day(9), calendar: cal).outcome, .missed)
        XCTAssertEqual(Metrics.workoutWeek([workout(2)], weekStart: day(2), goals: nil, today: day(9), calendar: cal).outcome, .noGoal)
    }

    // MARK: steps as a weekly average
    func testStepsGoalModes() {
        let daily = GoalSet(stepsDaily: 8000)
        let avg = GoalSet(stepsDaily: 8000, stepsIsWeeklyAverage: true)
        XCTAssertEqual(daily.dailyStepsGoal, 8000); XCTAssertNil(daily.weeklyAverageStepsGoal)
        XCTAssertNil(avg.dailyStepsGoal); XCTAssertEqual(avg.weeklyAverageStepsGoal, 8000)
        XCTAssertTrue(daily.hasDailyGoals); XCTAssertFalse(daily.hasWeeklyGoals)
        XCTAssertFalse(avg.hasDailyGoals); XCTAssertTrue(avg.hasWeeklyGoals)
        // a single low day only matters in daily mode
        let low = steps(3, 1000)
        XCTAssertEqual(Metrics.dayGoalStatus(low, goals: daily).steps, false)
        XCTAssertNil(Metrics.dayGoalStatus(low, goals: avg).steps)
    }
    func testStepsWeeklyAverageIsJudgedOnTheWeek() {
        let avg = GoalSet(stepsDaily: 8000, stepsIsWeeklyAverage: true)
        let days = (2...8).map { steps($0, $0 == 3 ? 4000 : 9000) }            // one low day: (6×9000+4000)/7 = 8285
        let w = Metrics.stepsWeekStatus(days, weekStart: day(2), goals: avg, today: day(9), calendar: cal)
        XCTAssertEqual(w.outcome, .met)
        XCTAssertEqual(w.dailyTarget!, 8000, accuracy: 1e-9)
        let weak = (2...8).map { steps($0, 7000) }
        XCTAssertEqual(Metrics.stepsWeekStatus(weak, weekStart: day(2), goals: avg, today: day(9), calendar: cal).outcome, .missed)
        // at or over: still open mid-week even if the running average is low
        XCTAssertEqual(Metrics.stepsWeekStatus([steps(2, 1000)], weekStart: day(2), goals: avg, today: day(3), calendar: cal).outcome, .inProgress)
    }

    // MARK: all weekly goals together
    func testWeeklyOutcomeNeedsEveryWeeklyGoal() {
        let g = GoalSet(caloriesWeekly: 14000, stepsDaily: 8000, stepsIsWeeklyAverage: true, workoutDaysWeekly: 2)
        func day7(_ n: Int, kcal: Int, st: Int, perf: Bool) -> DaySnapshot {
            DaySnapshot(date: day(n), weightKg: nil, logged: [.food, .steps], calories: kcal, steps: st,
                        ratings: perf ? ["performance": 4] : [:])
        }
        let good = (2...8).map { day7($0, kcal: 2000, st: 9000, perf: $0 <= 3) }
        XCTAssertEqual(Metrics.weeklyOutcome(good, weekStart: day(2), goals: g, today: day(9), calendar: cal), .met)
        let noWorkouts = (2...8).map { day7($0, kcal: 2000, st: 9000, perf: false) }
        XCTAssertEqual(Metrics.weeklyOutcome(noWorkouts, weekStart: day(2), goals: g, today: day(9), calendar: cal), .missed)
        XCTAssertEqual(Metrics.weeklyOutcome(good, weekStart: day(2), goals: GoalSet(proteinDaily: 100), today: day(9), calendar: cal), .noGoal)
        XCTAssertEqual(Metrics.weeklyOutcome(Array(good.prefix(2)), weekStart: day(2), goals: g, today: day(3), calendar: cal), .inProgress)
    }
    func testWeeklyStreakCountsWorkoutsToo() {
        let g = GoalSet(workoutDaysWeekly: 1)
        let tl = GoalTimeline(byWeek: [day(2): g])
        let days = [workout(3), workout(10), workout(24)]       // weeks of 2, 9 and 23 Nov; the 16th has none
        let s = Metrics.weeklyStreak(days, timeline: tl, today: day(30), calendar: cal)
        XCTAssertEqual(s.longest, 2); XCTAssertEqual(s.current, 1)      // 2,9 met; 16 missed; 23 met; 30 in progress
    }

    // MARK: compliance
    func fullDay(_ n: Int, perf: Int? = 4, na: Bool = false) -> DaySnapshot {
        var s = DaySnapshot(date: day(n), weightKg: 80, logged: Set(Tracker.allCases), complete: Set(Tracker.allCases),
                            calories: 2000, proteinG: 150, waterMl: 2500, steps: 9000, ratings: [:], performanceNA: na)
        if let perf { s.ratings["performance"] = perf }
        return s
    }
    func testComplianceNeedsTheWeeksWorkoutTargetToStayReachable() {
        let tl = GoalTimeline(byWeek: [day(2): GoalSet(workoutDaysWeekly: 3)])
        let req = Set(Tracker.allCases)
        // Wed 4 Nov: 3 workouts needed; Mon n/a, Tue n/a, Wed today unanswered → 0 + (Wed..Sun = 5) ≥ 3, on track
        let ok = [fullDay(2, perf: nil, na: true), fullDay(3, perf: nil, na: true), fullDay(4, perf: 4)]
        XCTAssertEqual(Metrics.compliance(ok, today: day(4), windowDays: 3, required: req, timeline: tl, calendar: cal).compliedDays, 3)
        // Sat 7 Nov: only Sat, Sun left and none done → 0 + 2 < 3: every day of the week is out
        let bad = (2...6).map { fullDay($0, perf: nil, na: true) }
        XCTAssertEqual(Metrics.compliance(bad, today: day(7), windowDays: 6, required: req, timeline: tl, calendar: cal).compliedDays, 0)
    }
    func testComplianceUsesWeeklyAverageStepsOnceTheWeekIsFinished() {
        let tl = GoalTimeline(byWeek: [day(2): GoalSet(stepsDaily: 10000, stepsIsWeeklyAverage: true)])
        let req = Set(Tracker.allCases)
        let week = (2...8).map { fullDay($0) }                  // 9,000 steps a day against a 10,000 average goal
        // Open week: it can still average out, so nothing is penalised yet.
        XCTAssertEqual(Metrics.compliance(Array(week.prefix(3)), today: day(4), windowDays: 3, required: req, timeline: tl, calendar: cal).compliedDays, 3)
        // Finished week short of the average: no day complies.
        XCTAssertEqual(Metrics.compliance(week, today: day(9), windowDays: 8, required: req, timeline: tl, calendar: cal).compliedDays, 0)
    }
}

final class DayLogCheckInTests: XCTestCase {
    func fullRatings(_ log: DayLog) {
        log.sleep = 4; log.fatigue = 2; log.stress = 2; log.hunger = 3; log.appetite = 3; log.soreness = 2
    }
    func testNaCountsAsAnsweredForCompleteness() {
        let log = DayLog(day: Date())
        fullRatings(log)
        XCTAssertFalse(log.completeTrackers.contains(.checkIn))        // performance still unanswered
        log.performanceNA = true
        XCTAssertTrue(log.completeTrackers.contains(.checkIn))         // n/a is an answer
        XCTAssertNil(log.snapshot.ratings["performance"])              // but not a workout
        XCTAssertTrue(log.snapshot.performanceNA)
    }
    func testNaAloneCountsAsLoggedButNotComplete() {
        let log = DayLog(day: Date())
        log.performanceNA = true
        XCTAssertTrue(log.loggedTrackers.contains(.checkIn))
        XCTAssertFalse(log.completeTrackers.contains(.checkIn))
    }
}
