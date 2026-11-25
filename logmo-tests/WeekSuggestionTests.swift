import XCTest
import SwiftData
@testable import logmo

final class WeekSuggestionTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }   // Mon 2 Nov 2026

    let goals = GoalSet(caloriesWeekly: 14700, proteinDaily: 150, stepsDaily: 10000, waterDailyMl: 2500, workoutDaysWeekly: 4)   // 2,100/day

    /// A full week 2–8 Nov with a weight change of `perDay` kg a day.
    func week(perDay: Double = -0.05, ratings: [String: Int] = ["sleep": 4, "fatigue": 3, "soreness": 3, "performance": 4],
              sick: Set<Int> = [], period: Set<Int> = [], steps: Int = 10000, calories: Int = 2050) -> [DaySnapshot] {
        (2...8).map { n in
            var s = DaySnapshot(date: day(n), weightKg: 80 + perDay * Double(n - 2), logged: Set(Tracker.allCases), complete: Set(Tracker.allCases),
                                calories: calories, proteinG: 150, carbsG: 220, fatG: 60, waterMl: 2500, steps: steps, ratings: ratings)
            s.isSick = sick.contains(n); s.onPeriod = period.contains(n)
            return s
        }
    }
    func summary(_ kind: CampaignKind, _ snaps: [DaySnapshot], cycle: Bool = true, sick: Bool = true) -> WeekSummary {
        let c = CampaignInfo(number: 1, kind: kind, start: day(2), plannedWeeks: 12)
        return SuggestionRules.summary(campaign: c, snaps: snaps, current: goals, window: .thisWeekSoFar,
                                       includeCycle: cycle, includeSick: sick, today: day(8), calendar: cal)
    }

    func testSummaryHoldsOnlyNumbers() {
        let s = summary(.cut, week())
        XCTAssertEqual(s.daysCovered, 7); XCTAssertEqual(s.daysLogged, 7)
        XCTAssertEqual(s.avgCalories, 2050); XCTAssertEqual(s.avgSteps, 10000); XCTAssertEqual(s.workoutDays, 7)
        XCTAssertEqual(s.weightChangeKgPerWeek!, -0.35, accuracy: 0.02)
        XCTAssertEqual(s.ratingAverages["fatigue"], 3)
        XCTAssertEqual(s.periodDays, 0); XCTAssertEqual(s.sickDays, 0)
    }

    func testCycleAndSicknessCanBeLeftOut() {
        let snaps = week(sick: [3, 4], period: [2])
        let s = summary(.cut, snaps, cycle: false, sick: false)
        XCTAssertNil(s.periodDays); XCTAssertNil(s.sickDays)
        let t = summary(.cut, snaps)
        XCTAssertEqual(t.periodDays, 1); XCTAssertEqual(t.sickDays, 2)
    }

    func testAGoodCutHoldsCalories() {
        let p = SuggestionRules.baseline(summary(.cut, week(perDay: -0.07)))        // about -0.49 kg a week, 0.6%
        XCTAssertEqual(p.caloriesPerDay, 2100)
        XCTAssertEqual(p.proteinG, 150)
        XCTAssertGreaterThan(p.carbsG, 0); XCTAssertGreaterThan(p.fatG, 0)
    }

    func testAStalledCutLowersCaloriesWithinTheLimit() {
        let p = SuggestionRules.baseline(summary(.cut, week(perDay: 0)))
        XCTAssertEqual(p.caloriesPerDay, 2000)                                       // -100
        XCTAssertGreaterThanOrEqual(p.caloriesPerDay, 2100 - 150)
    }

    func testABulkThatIsNotGainingRaisesCalories() {
        XCTAssertEqual(SuggestionRules.baseline(summary(.bulk, week(perDay: 0))).caloriesPerDay, 2200)
    }

    func testSicknessNeverTightensACutAndLightensLifting() {
        let p = SuggestionRules.baseline(summary(.cut, week(perDay: 0, sick: [3, 4])))   // a stall that would normally cut harder
        XCTAssertGreaterThanOrEqual(p.caloriesPerDay, 2100)
        XCTAssertEqual(p.workoutDays, 3)
        XCTAssertLessThanOrEqual(p.steps, 10000)
    }

    func testPeriodWeekDoesNotReadAStallAsAReasonToCutHarder() {
        let p = SuggestionRules.baseline(summary(.cut, week(perDay: 0, period: [2, 3])))
        XCTAssertEqual(p.caloriesPerDay, 2100)
        XCTAssertTrue(p.reasons.contains { $0.lowercased().contains("period") })
    }

    func testStrainDropsALiftingDay() {
        let tired = ["sleep": 2, "fatigue": 5, "soreness": 4, "performance": 2]
        let p = SuggestionRules.baseline(summary(.cut, week(perDay: 0, ratings: tired)))
        XCTAssertEqual(p.workoutDays, 3)
        XCTAssertGreaterThanOrEqual(p.caloriesPerDay, 2100)
    }

    func testNotEnoughWeighInsHoldsCalories() {
        var snaps = week(); for i in snaps.indices where i > 0 { snaps[i].weightKg = nil }
        let p = SuggestionRules.baseline(summary(.cut, snaps))
        XCTAssertEqual(p.caloriesPerDay, 2100)
        XCTAssertTrue(p.reasons.first!.contains("weigh-ins"))
    }

    func testClampHoldsWhateverProposesTheNumbers() {
        let s = summary(.cut, week(perDay: 0, sick: [3]))
        var wild = PlanSuggestion(caloriesPerDay: 900, proteinG: 900, carbsG: -5, fatG: 5, steps: 40000, workoutDays: 7, waterMl: 99999, reasons: ["a", "", "b"])
        wild = SuggestionRules.clamp(wild, around: s)
        XCTAssertEqual(wild.caloriesPerDay, 2100)                                    // sick on a cut: no harder, and within 150
        XCTAssertEqual(wild.steps, 12000); XCTAssertEqual(wild.workoutDays, 5)
        XCTAssertEqual(wild.proteinG, 300); XCTAssertEqual(wild.carbsG, 0); XCTAssertEqual(wild.fatG, 20)
        XCTAssertEqual(wild.waterMl, 6000); XCTAssertEqual(wild.reasons, ["a", "b"])
        var low = PlanSuggestion(caloriesPerDay: 1000, proteinG: 100, carbsG: 100, fatG: 50, steps: 8000, workoutDays: 4, reasons: [])
        low = SuggestionRules.clamp(low, around: summary(.maintenance, week()))
        XCTAssertEqual(low.caloriesPerDay, 1950)                                     // at most 150 below 2,100
    }

    func testTheSuggestionKeepsTheJudgingModes() {
        var base = goals; base.caloriesAtOrUnder = false; base.stepsIsWeeklyAverage = true
        let g = PlanSuggestion(caloriesPerDay: 2000, proteinG: 150, carbsG: 210, fatG: 58, steps: 9500, workoutDays: 3, waterMl: 2500, reasons: []).goalSet(keeping: base)
        XCTAssertEqual(g.caloriesWeekly, 14000); XCTAssertFalse(g.caloriesAtOrUnder); XCTAssertTrue(g.stepsIsWeeklyAverage)
        XCTAssertEqual(g.carbsDaily, 210); XCTAssertEqual(g.fatDaily, 58)
        XCTAssertTrue(g.hasDailyGoals)                                               // carbs and fat don't change what is judged
        XCTAssertFalse(GoalSet(carbsDaily: 200, fatDaily: 60).hasDailyGoals)
    }

    func testThePromptHoldsNoNamesOrDates() {
        let s = summary(.cut, week(sick: [3], period: [2]))
        let text = AIAdvisor.prompt(for: s, baseline: SuggestionRules.baseline(s))
        XCTAssertTrue(text.contains("Campaign: Cut, week 1 of 12"))
        XCTAssertTrue(text.contains("Sick days this week: 1")); XCTAssertTrue(text.contains("Period days this week: 1"))
        XCTAssertFalse(text.contains("2026")); XCTAssertFalse(text.contains("Nov"))
    }
}

@MainActor
final class GuidanceGoalsTests: XCTestCase {
    var container: ModelContainer?
    func testCarbsAndFatGuidanceSurviveSavingBackupAndNewCampaigns() throws {
        let c = try ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container = c
        let context = c.mainContext
        CampaignStore.ensureDefault(context)
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
