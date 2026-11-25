import XCTest
import SwiftData
@testable import logmo

final class WeekSuggestionTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }   // Mon 2 Nov 2026; Sun 22 Nov is "today"

    let goals = GoalSet(caloriesWeekly: 14700, proteinDaily: 150, stepsDaily: 10000, waterDailyMl: 2500, workoutDaysWeekly: 4)   // 2,100 a day
    let calm = ["sleep": 4, "fatigue": 2, "soreness": 2, "performance": 4, "hunger": 3, "stress": 2, "appetite": 3]

    /// Daily logs from `from` to 22 Nov. A nil value means "not logged that day", never zero.
    func data(from: Int = 2, weightPerDay: Double = -0.07, calories: Int? = 2100, steps: Int? = 10000,
              ratings: [String: Int]? = nil, sick: Set<Int> = [], period: Set<Int> = [],
              weighOn: (Int) -> Bool = { _ in true }, jitter: (Int) -> Double = { _ in 0 },
              hr: (Int) -> Int? = { _ in nil }, hrv: (Int) -> Int? = { _ in nil }, sleep: Int? = nil) -> [DaySnapshot] {
        (from...22).map { n in
            var logged: Set<Tracker> = []
            let w: Double? = weighOn(n) ? 80 + weightPerDay * Double(n - 2) + jitter(n) : nil
            if w != nil { logged.insert(.weight) }
            if calories != nil { logged.insert(.food) }
            if steps != nil { logged.insert(.steps) }
            var s = DaySnapshot(date: day(n), weightKg: w, logged: logged, complete: logged, calories: calories, proteinG: calories == nil ? nil : 150,
                                carbsG: calories == nil ? nil : 220, fatG: calories == nil ? nil : 60, waterMl: 2500, steps: steps, ratings: ratings ?? calm)
            if !s.ratings.isEmpty { s.logged.insert(.checkIn) }
            s.isSick = sick.contains(n); s.onPeriod = period.contains(n)
            s.restingHR = hr(n); s.hrv = hrv(n); s.sleepMinutes = sleep
            return s
        }
    }

    func summary(_ kind: CampaignKind, _ snaps: [DaySnapshot], goals g: GoalSet? = nil, cycle: Bool = true, sick: Bool = true) -> WeekSummary {
        let c = CampaignInfo(number: 1, kind: kind, start: day(2), plannedWeeks: 12)
        return SuggestionRules.summary(campaign: c, snaps: snaps, current: g ?? goals, window: .thisWeekSoFar,
                                       includeCycle: cycle, includeSick: sick, today: day(22), calendar: cal)
    }
    func suggestion(_ kind: CampaignKind, _ snaps: [DaySnapshot], goals g: GoalSet? = nil) -> PlanSuggestion {
        SuggestionRules.baseline(summary(kind, snaps, goals: g))
    }
    func text(_ p: PlanSuggestion) -> String { ([p.headline, p.note ?? ""] + p.evidence + p.cautions + p.needMoreData).joined(separator: " ") }

    // MARK: Facts are calculated, from what was logged

    func testSummaryHoldsOnlyCalculatedNumbers() {
        let s = summary(.cut, data())
        XCTAssertEqual(s.daysCovered, 7); XCTAssertEqual(s.daysLogged, 7)
        XCTAssertEqual(s.avgCalories, 2100); XCTAssertEqual(s.avgSteps, 10000); XCTAssertEqual(s.calorieDays, 7)
        XCTAssertEqual(s.weighIns, 21); XCTAssertEqual(s.weighSpanDays, 20)
        XCTAssertEqual(s.weightChangeKgPerWeek!, -0.49, accuracy: 0.02)
        XCTAssertEqual(s.ratingAverages["fatigue"], 2)
    }

    func testMissingLogsAreNeverZero() {
        let s = summary(.cut, data(calories: nil, steps: nil))
        XCTAssertNil(s.avgCalories); XCTAssertNil(s.avgSteps)
        XCTAssertEqual(s.calorieDays, 0); XCTAssertEqual(s.stepsDays, 0)
        let p = SuggestionRules.baseline(s)
        XCTAssertTrue(p.evidence.contains { $0.contains("No calories were logged") })
        XCTAssertEqual(p.steps, 10000)                                              // no steps data: the goal is left alone
    }

    func testCycleAndSicknessCanBeLeftOut() {
        let snaps = data(sick: [20, 21], period: [16])
        let off = summary(.cut, snaps, cycle: false, sick: false)
        XCTAssertNil(off.periodDays); XCTAssertNil(off.sickDays)
        let on = summary(.cut, snaps)
        XCTAssertEqual(on.periodDays, 1); XCTAssertEqual(on.sickDays, 2)
    }

    // MARK: Confidence

    func testInsufficientHistoryKeepsTargetsAndSaysWhatIsNeeded() {
        let p = suggestion(.cut, data(from: 20, weightPerDay: 0))
        XCTAssertEqual(p.caloriesPerDay, 2100)
        XCTAssertEqual(p.confidence, .low)
        XCTAssertTrue(p.headline.contains("for now"))
        XCTAssertTrue(p.needMoreData.contains { $0.contains("Weigh in") })
        XCTAssertTrue(p.evidence.first!.contains("aren't enough weigh-ins"))
    }

    func testConfidenceIsPerMetric() {
        // Calorie logs every day, but weigh-ins on only three days: nutrition is fine, the trend isn't.
        let s = summary(.cut, data(weightPerDay: 0, weighOn: { [2, 12, 22].contains($0) }))
        let a = SuggestionRules.assess(s)
        XCTAssertEqual(a.confidence.nutrition, .high); XCTAssertEqual(a.confidence.weight, .low)
        XCTAssertEqual(a.confidence.forCalories, .low)
        XCTAssertEqual(SuggestionRules.baseline(s).caloriesPerDay, 2100)
    }

    func testFullHistoryGivesHighConfidence() {
        XCTAssertEqual(SuggestionRules.baseline(summary(.cut, data())).confidence, .high)
    }

    func testScatteredWeighInsLowerConfidenceAndOneOutlierDoesNotMoveTheTarget() {
        let calmA = SuggestionRules.assess(summary(.cut, data()))
        let outlier = data(jitter: { $0 == 18 ? 3.0 : 0 })                          // one odd weigh-in
        let s = summary(.cut, outlier)
        let a = SuggestionRules.assess(s)
        XCTAssertLessThan(a.confidence.weight, calmA.confidence.weight)
        XCTAssertEqual(SuggestionRules.baseline(s).caloriesPerDay, 2100)            // still on track, so unchanged
    }

    // MARK: Progress by campaign

    func testACutOnTrackKeepsCalories() {
        let p = suggestion(.cut, data(weightPerDay: -0.07))
        XCTAssertEqual(p.caloriesPerDay, 2100)
        XCTAssertTrue(p.headline.hasPrefix("Keep calories at 2,100"))
        XCTAssertTrue(p.evidence.first!.contains("in the range this campaign aims for"))
    }

    func testABulkOnTrackKeepsCalories() {
        XCTAssertEqual(suggestion(.bulk, data(weightPerDay: 0.04)).caloriesPerDay, 2100)
    }

    func testMaintenanceThatIsStableKeepsCalories() {
        XCTAssertEqual(suggestion(.maintenance, data(weightPerDay: 0)).caloriesPerDay, 2100)
    }

    func testACutLosingTooFastRaisesCalories() {
        let p = suggestion(.cut, data(weightPerDay: -0.15))
        XCTAssertEqual(p.caloriesPerDay, 2200)
        XCTAssertTrue(p.headline.contains("Raise calories by 100"))
    }

    func testAPlateauWithGoodAdherenceLowersCaloriesModestly() {
        let p = suggestion(.cut, data(weightPerDay: 0, ratings: calm))
        XCTAssertEqual(p.caloriesPerDay, 2000)
        XCTAssertEqual(p.confidence, .high)
    }

    func testAPlateauWithPoorAdherenceIsNotATargetProblem() {
        let p = suggestion(.cut, data(weightPerDay: 0, calories: 2500))              // eating well above the target
        XCTAssertEqual(p.caloriesPerDay, 2100)
        XCTAssertTrue(p.cautions.contains { $0.contains("following it more closely") })
    }

    func testABulkNotGainingWithGoodAdherenceRaisesCalories() {
        XCTAssertEqual(suggestion(.bulk, data(weightPerDay: 0)).caloriesPerDay, 2200)
    }

    func testABulkNotGainingBecauseOfUnderEatingKeepsTheTarget() {
        let p = suggestion(.bulk, data(weightPerDay: 0, calories: 1700))
        XCTAssertEqual(p.caloriesPerDay, 2100)
        XCTAssertTrue(p.cautions.contains { $0.contains("following it more closely") })
    }

    func testAMaintenanceDriftUpLowersAndDriftDownRaises() {
        XCTAssertEqual(suggestion(.maintenance, data(weightPerDay: 0.1)).caloriesPerDay, 2000)
        XCTAssertEqual(suggestion(.maintenance, data(weightPerDay: -0.1)).caloriesPerDay, 2200)
    }

    func testNoCalorieChangeWithoutCalorieLogs() {
        let p = suggestion(.cut, data(weightPerDay: 0, calories: nil))
        XCTAssertEqual(p.caloriesPerDay, 2100)
        XCTAssertEqual(p.metricConfidence.nutrition, .low)
        XCTAssertTrue(p.needMoreData.contains { $0.contains("Log your calories") })
    }

    func testContradictoryLogsAndScaleKeepTheTarget() {
        let p = suggestion(.cut, data(weightPerDay: 0.05, calories: 1900))           // eating under target yet gaining
        XCTAssertEqual(p.caloriesPerDay, 2100)
        XCTAssertTrue(p.cautions.contains { $0.contains("opposite directions") })
    }

    // MARK: Recovery and biofeedback

    func testHighFatigueBlocksALowerCutTargetAndLightensLifting() {
        let tired = ["sleep": 3, "fatigue": 5, "soreness": 4, "performance": 3, "hunger": 3]
        let p = suggestion(.cut, data(weightPerDay: 0, ratings: tired))
        XCTAssertEqual(p.caloriesPerDay, 2100)
        XCTAssertEqual(p.workoutDays, 3)
        XCTAssertTrue(p.cautions.contains { $0.contains("recovery looks strained") })
        XCTAssertTrue(p.evidence.contains { $0.contains("not a judgement on whether training is safe") })
    }

    func testSicknessBlocksTighteningAndLeavesStepsAlone() {
        let p = suggestion(.cut, data(weightPerDay: 0, steps: 4000, sick: [20, 21]))
        XCTAssertEqual(p.caloriesPerDay, 2100)
        XCTAssertEqual(p.workoutDays, 3)
        XCTAssertEqual(p.steps, 10000)                                               // no rework of steps during illness
        XCTAssertTrue(p.cautions.contains { $0.contains("you were sick") })
    }

    func testAPeriodWeekDoesNotLowerACutTarget() {
        let p = suggestion(.cut, data(weightPerDay: 0, period: [20, 21]))
        XCTAssertEqual(p.caloriesPerDay, 2100)
        XCTAssertTrue(p.cautions.contains { $0.contains("period days can mask progress") })
    }

    func testContradictoryBiofeedbackIsFlaggedAndNotTreatedAsGoodRecovery() {
        let odd = ["sleep": 4, "fatigue": 2, "soreness": 2, "performance": 4, "hunger": 4, "appetite": 1]
        let s = summary(.cut, data(ratings: odd))
        let a = SuggestionRules.assess(s)
        XCTAssertEqual(a.recovery, .mixed)
        XCTAssertTrue(a.cautions.contains { $0.contains("don't usually go together") })
        XCTAssertEqual(SuggestionRules.baseline(s).workoutDays, 4)                   // mixed signals: no change either way
    }

    func testGoodRecoveryNeverRaisesLifting() {
        let p = suggestion(.cut, data(weightPerDay: -0.07, ratings: calm))
        XCTAssertEqual(SuggestionRules.assess(summary(.cut, data())).recovery, .good)
        XCTAssertEqual(p.workoutDays, 4)
        XCTAssertTrue(p.evidence.contains { $0.contains("self-reports") })
    }

    func testPersistentHungerAndFatigueOnACutReviewsTheTarget() {
        let hungry = ["sleep": 3, "fatigue": 4, "soreness": 3, "performance": 3, "hunger": 5]
        let p = suggestion(.cut, data(weightPerDay: -0.07, ratings: hungry))
        XCTAssertEqual(p.caloriesPerDay, 2200)
        XCTAssertTrue(p.cautions.contains { $0.contains("Hunger and fatigue are both high") })
    }

    // MARK: Health context

    func testHealthSleepAndHeartRateAppearAsEvidence() {
        let p = suggestion(.cut, data(hr: { _ in 56 }, hrv: { _ in 48 }, sleep: 420))
        let t = text(p)
        XCTAssertTrue(t.contains("average of 7.0 hours asleep on 7 nights"), t)
        XCTAssertTrue(t.contains("Resting heart rate averaged 56 bpm"), t)
    }

    func testRisingHeartRateAndFallingHRVSoftenRecoveryButDoNotChangeTraining() {
        let worse = data(hr: { $0 >= 16 ? 62 : 55 }, hrv: { $0 >= 16 ? 38 : 50 })       // this week vs the week before
        let s = summary(.cut, worse)
        let a = SuggestionRules.assess(s)
        XCTAssertEqual(s.restingHRChange!, 7, accuracy: 0.01)
        XCTAssertEqual(a.recovery, .mixed)                                               // would otherwise be good
        XCTAssertTrue(a.cautions.contains { $0.contains("context, not a verdict on training") })
        let p = SuggestionRules.baseline(s)
        XCTAssertEqual(p.workoutDays, 4); XCTAssertEqual(p.caloriesPerDay, 2100)         // nothing is changed on this alone
        let steady = SuggestionRules.assess(summary(.cut, data(hr: { _ in 56 }, hrv: { _ in 48 })))
        XCTAssertEqual(steady.recovery, .good)
    }

    func testTheModelSeesTheHealthFacts() {
        let s = summary(.cut, data(hr: { _ in 56 }, hrv: { _ in 48 }, sleep: 420))
        let t = AIAdvisor.facts(s, SuggestionRules.assess(s))
        XCTAssertTrue(t.contains("resting heart rate bpm: average 56")); XCTAssertTrue(t.contains("hrv ms: average 48"))
        XCTAssertTrue(t.contains("sleep recorded by Health: 7.0 hours"))
    }

    // MARK: Adherence is not miscalibration

    func testMissedWorkoutsDoNotLowerTheGoalWhenRecoveryIsFine() {
        var snaps = data()
        for i in snaps.indices where i % 2 == 0 { snaps[i].ratings["performance"] = nil }   // trains on fewer days than the goal
        let p = SuggestionRules.baseline(summary(.cut, snaps))
        XCTAssertEqual(p.workoutDays, 4)
        XCTAssertTrue(p.evidence.contains { $0.contains("isn't lowered just because") })
    }

    func testAStepsGoalFarAboveWhatIsDoneIsRecalibrated_butOnlyWithEnoughData() {
        let p = suggestion(.cut, data(steps: 4000))
        XCTAssertLessThan(p.steps, 10000); XCTAssertGreaterThanOrEqual(p.steps, 8000)
        XCTAssertTrue(p.evidence.contains { $0.contains("steps goal comes down") })
        let few = suggestion(.cut, data(from: 20, steps: 4000))                      // only 3 days: too little to recalibrate
        XCTAssertEqual(few.steps, 10000)
    }

    // MARK: Safety

    func testALowCalorieTargetIsNeverLoweredEvenIfItExceedsTheFloor() {
        var low = goals; low.caloriesWeekly = 1300 * 7
        let p = suggestion(.cut, data(weightPerDay: 0, calories: 1300), goals: low)
        XCTAssertEqual(p.caloriesPerDay, 1300)
        XCTAssertTrue(p.cautions.contains { $0.contains("already low") })
        var mid = goals; mid.caloriesWeekly = 1450 * 7                                // above 1,200 but still treated as low
        XCTAssertEqual(suggestion(.cut, data(weightPerDay: 0, calories: 1450), goals: mid).caloriesPerDay, 1450)
    }

    func testATargetFarBelowMaintenanceFromTheLogsIsFlaggedEvenAboveTheFixedThreshold() {
        var g = goals; g.caloriesWeekly = 1800 * 7
        let s = summary(.cut, data(from: -38, weightPerDay: -0.1, calories: 1800), goals: g)       // two months: losing 0.7 kg a week on 1,800
        XCTAssertEqual(s.maintenanceSource, .trend)
        XCTAssertGreaterThan(s.estimatedMaintenance!, 2400)
        let p = SuggestionRules.baseline(s)
        XCTAssertGreaterThanOrEqual(p.caloriesPerDay, 1800)                                         // never lowered
        XCTAssertTrue(p.cautions.contains { $0.contains("already low") && $0.contains("below your estimated maintenance") }, p.cautions.joined(separator: "|"))
    }

    func testTheFormulaFlagsALowTargetBeforeTheLogsHaveBuiltAnEstimate() {
        var g = goals; g.caloriesWeekly = 1900 * 7
        let profile = MaintenanceProfile(sex: .male, age: 30, heightCm: 180, activity: .moderate)
        let c = CampaignInfo(number: 1, kind: .cut, start: day(2), plannedWeeks: 12)
        let s = SuggestionRules.summary(campaign: c, snaps: data(from: 17, weightPerDay: -0.05, calories: 1900), current: g, window: .thisWeekSoFar,
                                        includeCycle: true, includeSick: true, today: day(22), profile: profile, calendar: cal)
        XCTAssertEqual(s.maintenanceSource, .formula)
        let p = SuggestionRules.baseline(s)
        XCTAssertTrue(p.cautions.contains { $0.contains("already low") }, p.cautions.joined(separator: "|"))
        XCTAssertTrue(p.evidence.contains { $0.contains("formula estimate") })
    }

    func testMaintenanceFromTheLogsIsShownAsEvidenceAndSizesTheMove() {
        // Plateau on 2,100 with a lot of room: the move is the weekly limit of 100, and the evidence says why.
        let s = summary(.cut, data(from: -38, weightPerDay: 0, calories: 2100))
        let p = SuggestionRules.baseline(s)
        XCTAssertEqual(p.caloriesPerDay, 2000)
        XCTAssertTrue(p.evidence.contains { $0.contains("Your estimated maintenance is about 2,1") || $0.contains("Your estimated maintenance is about 2,0") })
        XCTAssertTrue(p.evidence.contains { $0.contains("Moving 100 now keeps the change gradual") })
    }

    func testASmallGapToTheTargetPaceGivesASmallMove() {
        // Maintenance about 2,100, a cut aims near -0.65% a week (about 570 kcal below maintenance), so a target of 1,600 is already
        // there; a stalled cut on 1,650 only needs a step of 50 to reach it.
        var g = goals; g.caloriesWeekly = 1650 * 7
        let s = summary(.cut, data(from: -38, weightPerDay: 0, calories: 1650), goals: g)
        let p = SuggestionRules.baseline(s)
        XCTAssertGreaterThanOrEqual(p.caloriesPerDay, 1650 - 100)
        XCTAssertLessThanOrEqual(p.caloriesPerDay, 1650)
    }

    func testWhenTheEstimateSaysTheTargetIsAlreadyAtPaceTheTargetStays() {
        // Cut stalling although intake sits far below estimated maintenance: the data disagree with themselves, so no change.
        var g = goals; g.caloriesWeekly = 1400 * 7
        let snaps = data(from: -38, weightPerDay: -0.07, calories: 2100)                          // building a ~2,650 maintenance
        var tail = snaps; for i in tail.indices where i >= tail.count - 21 { tail[i].calories = 1400; tail[i].weightKg = 80 - 0.07 * Double(i) }
        let s = summary(.cut, tail, goals: g)
        let p = SuggestionRules.baseline(s)
        XCTAssertGreaterThanOrEqual(p.caloriesPerDay, 1400)
    }

    func testThePromptCarriesTheMaintenanceFact() {
        let s = summary(.cut, data(from: -38, weightPerDay: -0.07))
        let t = AIAdvisor.facts(s, SuggestionRules.assess(s))
        XCTAssertTrue(t.contains("estimated maintenance kcal per day: "), t)
        XCTAssertTrue(t.contains("from weight trend and intake"))
    }

    func testAIChoicesAreClampedToWhatTheEvidenceSupports() {
        let s = summary(.cut, data(weightPerDay: 0))                                  // supports 2,100 down to 2,000
        let a = SuggestionRules.assess(s)
        XCTAssertEqual(a.allowedCalories, 2000...2100)
        let greedy = SuggestionRules.compose(s, a, calories: 900, steps: 40000, workouts: 7, source: .appleIntelligence)
        XCTAssertEqual(greedy.caloriesPerDay, 2000); XCTAssertEqual(greedy.steps, 10000); XCTAssertEqual(greedy.workoutDays, 4)
        let wild = SuggestionRules.clamp(PlanSuggestion(caloriesPerDay: 5000, proteinG: 900, carbsG: -5, fatG: 5, steps: 0, workoutDays: -3), around: s)
        XCTAssertEqual(wild.caloriesPerDay, 2100); XCTAssertEqual(wild.steps, 10000); XCTAssertEqual(wild.workoutDays, 4)    // nothing supports a change in these
    }

    func testAIcannotChangeCaloriesWhenConfidenceIsLow() {
        let s = summary(.cut, data(from: 20, weightPerDay: 0))
        let p = SuggestionRules.compose(s, SuggestionRules.assess(s), calories: 1800, steps: 10000, workouts: 4, source: .appleIntelligence)
        XCTAssertEqual(p.caloriesPerDay, 2100)
    }

    func testAIcannotCutHarderWhenSick() {
        let s = summary(.cut, data(weightPerDay: 0, sick: [21]))
        let p = SuggestionRules.compose(s, SuggestionRules.assess(s), calories: 1900, steps: 12000, workouts: 6, source: .appleIntelligence)
        XCTAssertEqual(p.caloriesPerDay, 2100); XCTAssertEqual(p.steps, 10000); XCTAssertLessThanOrEqual(p.workoutDays, 4)
    }

    func testMacrosAddUpToTheCalories() {
        for (kind, w) in [(CampaignKind.cut, 0.0), (.bulk, 0.0), (.maintenance, 0.1), (.cut, -0.15)] {
            let p = suggestion(kind, data(weightPerDay: w))
            let kcal = 4 * p.proteinG + 4 * p.carbsG + 9 * p.fatG
            XCTAssertLessThanOrEqual(abs(kcal - p.caloriesPerDay), 25, "\(kind) \(w): \(kcal) vs \(p.caloriesPerDay)")
        }
        let m = SuggestionRules.macros(calories: 1600, proteinGoal: 150, kind: .cut)
        XCTAssertLessThanOrEqual(abs(4 * m.protein + 4 * m.carbs + 9 * m.fat - 1600), 25)
    }

    func testKeptCaloriesKeepTheUsersOwnMacros() {
        var g = goals; g.carbsDaily = 230; g.fatDaily = 65
        let p = suggestion(.cut, data(weightPerDay: -0.07), goals: g)
        XCTAssertEqual(p.caloriesPerDay, 2100); XCTAssertEqual(p.carbsG, 230); XCTAssertEqual(p.fatG, 65)
    }

    func testTheSuggestionKeepsTheJudgingModes() {
        var base = goals; base.caloriesAtOrUnder = false; base.stepsIsWeeklyAverage = true
        let g = PlanSuggestion(caloriesPerDay: 2000, proteinG: 150, carbsG: 210, fatG: 58, steps: 9500, workoutDays: 3, waterMl: 2500).goalSet(keeping: base)
        XCTAssertEqual(g.caloriesWeekly, 14000); XCTAssertFalse(g.caloriesAtOrUnder); XCTAssertTrue(g.stepsIsWeeklyAverage)
        XCTAssertEqual(g.carbsDaily, 210); XCTAssertEqual(g.fatDaily, 58)
        XCTAssertTrue(g.hasDailyGoals)
        XCTAssertFalse(GoalSet(carbsDaily: 200, fatDaily: 60).hasDailyGoals)
    }

    // MARK: Explanations come from the facts

    func testExplanationsQuoteTheActualLoggedNumbers() {
        let p = suggestion(.cut, data(weightPerDay: -0.07, calories: 2050, steps: 9000))
        let t = text(p)
        XCTAssertTrue(t.contains("2,050 kcal a day against a goal of 2,100"))
        XCTAssertTrue(t.contains("logged on 7 of 7 days"))
        XCTAssertTrue(t.contains("9,000 a day against a goal of 10,000"))
        XCTAssertTrue(t.contains("21 weigh-ins"))
        XCTAssertFalse(t.contains("1700"))                                            // the old generic sentence is gone
    }

    func testThePromptHoldsFactsAndRangesButNoNamesOrDates() {
        let s = summary(.cut, data(sick: [21], period: [16]))
        let a = SuggestionRules.assess(s)
        let text = AIAdvisor.prompt(for: s, assessment: a)
        XCTAssertTrue(text.contains("campaign: Cut, week 3 of 12"))
        XCTAssertTrue(text.contains("sick days: 1")); XCTAssertTrue(text.contains("period days: 1"))
        XCTAssertTrue(text.contains("confidence: High")); XCTAssertTrue(text.contains("you may choose calories between"))
        XCTAssertFalse(text.contains("2026")); XCTAssertFalse(text.contains("Nov"))
    }

    // MARK: The model's note is checked

    func testANoteWithAnInventedNumberIsRejected() {
        let facts = "weight trend per week: -0.49 kg; calories per day: average 2100, goal 2100"
        XCTAssertNil(NoteValidator.clean("You lost 3 kg this week.", facts: facts, targets: [2100]))
        XCTAssertNil(NoteValidator.clean("Your average of 2,350 is above goal.", facts: facts, targets: [2100]))
        XCTAssertEqual(NoteValidator.clean("Your trend of -0.49 kg a week fits a cut; calories stay at 2,100.", facts: facts, targets: [2100]),
                       "Your trend of -0.49 kg a week fits a cut; calories stay at 2,100.")
    }

    func testANoteWithSafetyOrMedicalClaimsIsRejected() {
        let facts = "calories per day: average 2100"
        for bad in ["It is safe to train hard this week.", "That is not safe.", "This may be a diagnosis.", "Results are guaranteed.", "You must eat more."] {
            XCTAssertNil(NoteValidator.clean(bad, facts: facts, targets: []), bad)
        }
        XCTAssertNil(NoteValidator.clean("", facts: facts, targets: []))
        XCTAssertNil(NoteValidator.clean(String(repeating: "a", count: 400), facts: facts, targets: []))
    }
}

@MainActor
final class GuidanceGoalsTests: XCTestCase {
    var container: ModelContainer?
    func testCarbsAndFatGuidanceSurviveSavingBackupAndNewCampaigns() throws {
        let c = try ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container = c
        let context = c.mainContext
        CampaignStore.start(context, kind: .cut, targetKg: nil, start: Date(), weeks: 8, startWeightKg: 80)
        let camp = try context.fetch(FetchDescriptor<Campaign>())[0]
        let monday = Metrics.weekStart(of: Date())
        PlanStore.save(context, campaignID: camp.id, week: monday, goals: GoalSet(proteinDaily: 150, carbsDaily: 210, fatDaily: 58))
        let data = try Backup.encode(try Backup.make(context))
        try DataReset.deleteAll(context)
        try Backup.restore(try Backup.decode(data), into: context)
        let g = try context.fetch(FetchDescriptor<WeekGoal>()).first { $0.proteinDaily == 150 }
        XCTAssertEqual(g?.carbsDaily, 210); XCTAssertEqual(g?.fatDaily, 58)
    }
}

@MainActor
final class SuggestionTimeoutTests: XCTestCase {
    func testAnAnswerInTimeIsUsed() async {
        let r = await SuggestSheet.withTimeout(seconds: 2) { () -> Int? in try? await Task.sleep(for: .milliseconds(50)); return 7 }
        XCTAssertEqual(r.value, 7); XCTAssertFalse(r.timedOut)
    }

    func testASilentModelIsGivenUpOnAndTheCalculatedSuggestionStandsIn() async {
        let start = Date()
        let r = await SuggestSheet.withTimeout(seconds: 0.3) { () -> Int? in try? await Task.sleep(for: .seconds(5)); return 7 }
        XCTAssertNil(r.value); XCTAssertTrue(r.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)                          // did not wait for the model
    }

    func testAFailedModelFallsBackWithoutBeingCalledATimeout() async {
        let r = await SuggestSheet.withTimeout(seconds: 2) { () -> Int? in nil }
        XCTAssertNil(r.value); XCTAssertFalse(r.timedOut)
    }
}
