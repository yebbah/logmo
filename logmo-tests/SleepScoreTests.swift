import XCTest
import SwiftData
@testable import logmo

final class SleepScoreTests: XCTestCase {
    func testDurationTiers() {
        XCTAssertEqual(SleepScore.durationScore(480), 5)       // 8 h
        XCTAssertEqual(SleepScore.durationScore(450), 5)       // 7 h 30 min
        XCTAssertEqual(SleepScore.durationScore(449), 4)
        XCTAssertEqual(SleepScore.durationScore(405), 4)       // 6 h 45 min
        XCTAssertEqual(SleepScore.durationScore(404), 3)
        XCTAssertEqual(SleepScore.durationScore(360), 3)       // 6 h
        XCTAssertEqual(SleepScore.durationScore(359), 2)
        XCTAssertEqual(SleepScore.durationScore(270), 2)       // 4 h 30 min
        XCTAssertEqual(SleepScore.durationScore(269), 1)
        XCTAssertEqual(SleepScore.durationScore(570), 5)       // 9 h 30 min
        XCTAssertEqual(SleepScore.durationScore(571), 4)       // a very long night is not the top score
    }

    func testTheSampleNightOfTwoHoursFortySixIsAOneWithACaveat() {
        let r = SleepScore.score(asleepMinutes: 166)
        XCTAssertEqual(r.score, 1)
        XCTAssertEqual(r.headline, "2 h 46 min asleep: 1 of 5")
        XCTAssertTrue(r.detail.contains("far under the 7 to 9 hours"))
        XCTAssertNotNil(r.caveat)                                // under 3 hours: may be partial or a nap
        XCTAssertNil(SleepScore.score(asleepMinutes: 200).caveat)
    }

    // MARK: Stages

    func testGoodStagesKeepTheTopScoreAndCanLiftAGoodNightByOne() {
        let top = SleepScore.score(asleepMinutes: 480, awakeMinutes: 20, deepMinutes: 80, remMinutes: 110)       // unbroken, 17% deep, 23% REM
        XCTAssertEqual(top.score, 5); XCTAssertEqual(top.stageAdjustment, 0)
        XCTAssertTrue(top.detail.contains("deep 1 h 20 min (17%)")); XCTAssertTrue(top.detail.contains("REM 1 h 50 min (23%)"))
        XCTAssertTrue(top.detail.contains("keep it at the top"))
        let lifted = SleepScore.score(asleepMinutes: 410, awakeMinutes: 15, deepMinutes: 65, remMinutes: 90)     // 6 h 50 min is a 4 on duration
        XCTAssertEqual(lifted.score, 5); XCTAssertEqual(lifted.stageAdjustment, 1)
        XCTAssertTrue(lifted.detail.contains("raise the score by one"))
    }

    func testStagesCannotLiftANightUnderSixHours() {
        XCTAssertEqual(SleepScore.score(asleepMinutes: 340, awakeMinutes: 5, deepMinutes: 55, remMinutes: 75).score, 2)
    }

    func testWeakStagesLowerTheScore() {
        let weak = SleepScore.score(asleepMinutes: 480, awakeMinutes: 20, deepMinutes: 20, remMinutes: 40)       // 4% deep, 8% REM
        XCTAssertEqual(weak.score, 4); XCTAssertEqual(weak.stageAdjustment, -1)
        let veryWeak = SleepScore.score(asleepMinutes: 480, awakeMinutes: 100, deepMinutes: 10, remMinutes: 20)
        XCTAssertEqual(veryWeak.score, 3); XCTAssertEqual(veryWeak.stageAdjustment, -2)
        XCTAssertTrue(veryWeak.detail.contains("lower the score by two"))
    }

    func testABrokenNightAlwaysLosesAPointEvenWithGoodStages() {
        let r = SleepScore.score(asleepMinutes: 480, awakeMinutes: 150, deepMinutes: 80, remMinutes: 110)       // 76% unbroken
        XCTAssertEqual(r.score, 4); XCTAssertEqual(r.stageAdjustment, -1)
        XCTAssertTrue(r.detail.contains("awake 2 h 30 min (76% of the night asleep)"))
    }

    func testWithoutStageDataOnlyDurationCounts() {
        XCTAssertEqual(SleepScore.score(asleepMinutes: 480).score, 5)
        XCTAssertEqual(SleepScore.score(asleepMinutes: 480, awakeMinutes: 150).score, 5)                          // awake time alone, no stages: not judged
        XCTAssertEqual(SleepScore.score(asleepMinutes: 480, awakeMinutes: 20, deepMinutes: 80, remMinutes: nil).stageAdjustment, 0)
        XCTAssertEqual(SleepScore.score(asleepMinutes: 480).stageAdjustment, 0)
    }

    func testTheScoreNeverLeavesOneToFive() {
        XCTAssertEqual(SleepScore.score(asleepMinutes: 100, awakeMinutes: 100, deepMinutes: 1, remMinutes: 1).score, 1)
        XCTAssertEqual(SleepScore.score(asleepMinutes: 500, awakeMinutes: 5, deepMinutes: 90, remMinutes: 110).score, 5)
    }

    func testStageQualityWithoutTimeAwakeSharesTheWeightBetweenDeepAndREM() {
        XCTAssertEqual(SleepScore.stageQuality(asleep: 480, awake: nil, deep: 80, rem: 110), 1, accuracy: 1e-9)
        XCTAssertEqual(SleepScore.stageQuality(asleep: 480, awake: nil, deep: 20, rem: 110), 0.5, accuracy: 1e-9)
    }

    func testANightIsScoredOnlyOnceTheMorningIsOver() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.date(from: DateComponents(year: 2026, month: 11, day: 25))!
        let at = { (h: Int) in cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: h))! }
        XCTAssertFalse(SleepScore.isFinished(day: day, now: at(8), calendar: cal))
        XCTAssertTrue(SleepScore.isFinished(day: day, now: at(11), calendar: cal))
        XCTAssertTrue(SleepScore.isFinished(day: cal.date(byAdding: .day, value: -1, to: day)!, now: at(8), calendar: cal))
    }
}

@MainActor
final class SleepScoreSyncTests: XCTestCase {
    var container: ModelContainer?
    func makeContext() throws -> ModelContext {
        let c = try ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container = c; return c.mainContext
    }
    var today: Date { Calendar.current.startOfDay(for: Date()) }

    func testTheScoreFillsTheSleepRatingAsAHealthValue() throws {
        let context = try makeContext()
        var h = HealthDay(day: today, sleepMinutes: 166); h.sleepScore = 1
        HealthSync.apply([h], to: context, topics: [.sleep], today: today)
        let log = try context.fetch(FetchDescriptor<DayLog>())[0]
        XCTAssertEqual(log.sleep, 1); XCTAssertEqual(log.imported, [.sleep]); XCTAssertEqual(log.healthSleepMinutes, 166)
    }

    func testATypedSleepRatingStandsAgainstARefresh_andSyncOverwritesIt() throws {
        let context = try makeContext()
        let log = DayLog(day: today); log.sleep = 4; context.insert(log); try context.save()
        var h = HealthDay(day: today, sleepMinutes: 166); h.sleepScore = 1
        HealthSync.apply([h], to: context, topics: [.sleep], today: today)
        XCTAssertEqual(log.sleep, 4)
        HealthSync.apply([h], to: context, topics: [.sleep], today: today, overwriteDay: today)
        XCTAssertEqual(log.sleep, 1)
    }

    func testAnUnfinishedNightKeepsTheHoursButSetsNoRating() throws {
        let context = try makeContext()
        HealthSync.apply([HealthDay(day: today, sleepMinutes: 166)], to: context, topics: [.sleep], today: today)   // no score yet
        let log = try context.fetch(FetchDescriptor<DayLog>())[0]
        XCTAssertNil(log.sleep); XCTAssertEqual(log.healthSleepMinutes, 166)
    }

    func testChangingTheScoredRatingMakesItTheUsers() throws {
        let context = try makeContext()
        var h = HealthDay(day: today, sleepMinutes: 166); h.sleepScore = 1
        HealthSync.apply([h], to: context, topics: [.sleep], today: today)
        let log = try context.fetch(FetchDescriptor<DayLog>())[0]
        var d = DayDraft(log, unit: .kg); d.ratings[.sleep] = 3
        d.apply(to: log, unit: .kg)
        XCTAssertEqual(log.sleep, 3); XCTAssertEqual(log.overridden, [.sleep])
        HealthSync.apply([h], to: context, topics: [.sleep], today: today)
        XCTAssertEqual(log.sleep, 3)
    }

    func testSleepStageMinutesSurviveBackup() throws {
        let context = try makeContext()
        var h = HealthDay(day: today, sleepMinutes: 440, sleepAwakeMinutes: 30, sleepDeepMinutes: 70, sleepREMMinutes: 60); h.sleepScore = 5
        HealthSync.apply([h], to: context, topics: [.sleep], today: today)
        let data = try Backup.encode(try Backup.make(context))
        try DataReset.deleteAll(context)
        try Backup.restore(try Backup.decode(data), into: context)
        let back = try context.fetch(FetchDescriptor<DayLog>())[0]
        XCTAssertEqual(back.healthSleepAwakeMinutes, 30); XCTAssertEqual(back.healthSleepDeepMinutes, 70); XCTAssertEqual(back.healthSleepREMMinutes, 60); XCTAssertEqual(back.sleep, 5)
    }
}
