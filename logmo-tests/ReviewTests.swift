import XCTest
@testable import logmo

final class ReviewTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }   // Mon 2 Nov 2026; Sun 22 Nov is the review day

    let goals = GoalSet(caloriesWeekly: 14700, proteinDaily: 150, stepsDaily: 10000, waterDailyMl: 2500, workoutDaysWeekly: 4)
    func camp(kind: CampaignKind = .cut) -> CampaignInfo { CampaignInfo(number: 1, kind: kind, targetWeightKg: 76, start: day(2), plannedWeeks: 12) }

    /// Seven logged days a week from the 2nd to the 22nd, losing 0.07 kg a day, eating and moving as planned. `fatigue` varies by day.
    func data(weightPerDay: Double = -0.07, fatigue: (Int) -> Int = { _ in 2 }, calories: Int? = 2100, from: Int = 2) -> [DaySnapshot] {
        (from...22).map { n in
            var logged: Set<Tracker> = [.weight, .steps, .water]
            if calories != nil { logged.insert(.food) }
            var s = DaySnapshot(date: day(n), weightKg: 80 + weightPerDay * Double(n - 2), logged: logged, complete: logged, calories: calories,
                                proteinG: 150, carbsG: 220, fatG: 60, waterMl: 2500, steps: 10000,
                                ratings: ["sleep": 4, "fatigue": fatigue(n), "stress": 2, "hunger": 3, "performance": 4, "appetite": 3, "soreness": 2])
            s.logged.insert(.checkIn); s.complete.insert(.checkIn)
            return s
        }
    }

    func review(_ snaps: [DaySnapshot], kind: CampaignKind = .cut, week: Int = 16, today: Int = 22, measurements: [MeasureEntry] = [], c: CampaignInfo? = nil) -> WeeklyReview {
        let camp = c ?? self.camp(kind: kind)
        let trend = Metrics.weightTrend(snaps, through: day(today), smoothingDays: 16, seeds: [:], calendar: cal)
        let weeks = Dictionary(uniqueKeysWithValues: stride(from: 2, through: 22, by: 7).map { (day($0), goals) })
        return ReviewRules.review(campaign: camp, snaps: snaps, timeline: GoalTimeline(byWeek: weeks), measurements: measurements, trend: trend, maintenance: nil,
                                  week: day(week), today: day(today), required: [], includeCycle: true, includeSick: true, useLb: false, calendar: cal)
    }
    func metric(_ r: WeeklyReview, _ id: String) -> ReviewMetric? { r.metrics.first { $0.id == id } }

    func testAWeekOnPlanIsOnTrackAndEveryRowIsRead() {
        let r = review(data())
        XCTAssertEqual(r.verdict, .onTrack)
        XCTAssertEqual(r.daysCovered, 7); XCTAssertTrue(r.isFullWeek)
        for id in ["weight", "calories", "protein", "steps", "water", "training"] { XCTAssertEqual(metric(r, id)?.mark, .good, id) }
        XCTAssertTrue(metric(r, "weight")!.text.contains("inside the range a cut aims for"))
        XCTAssertTrue(metric(r, "weight")!.text.contains("above your 76.0 kg target"))
        XCTAssertEqual(metric(r, "protein")?.value, "7 of 7 days")
        XCTAssertEqual(metric(r, "training")?.value, "7 lifting days")
        XCTAssertNotNil(metric(r, "calories")?.previous)                                           // last week's value sits beside it
        XCTAssertTrue(r.summary.hasPrefix("A solid week."))
    }

    func testAWeightMovingTheWrongWayIsFlaggedAndLowersTheVerdict() {
        let r = review(data(weightPerDay: 0.05))
        XCTAssertEqual(metric(r, "weight")?.mark, .warn)
        XCTAssertTrue(metric(r, "weight")!.text.contains("wrong way for a cut"))
        XCTAssertNotEqual(r.verdict, .onTrack)
    }

    func testRisingFatigueIsWorthWatching() {
        let r = review(data(fatigue: { $0 >= 16 ? 3 : 2 }))                                          // fatigue up a point on last week
        XCTAssertEqual(metric(r, "felt")?.mark, .warn)
        XCTAssertTrue(metric(r, "felt")!.text.contains("Fatigue rose 1.0"))
        XCTAssertEqual(r.verdict, .mostlyOnTrack)
        XCTAssertEqual(r.ratings.first { $0.rating == .fatigue }?.change ?? 0, 1.0, accuracy: 0.001)
    }

    func testTooLittleLoggedSaysSoInsteadOfJudging() {
        let r = review(data(from: 21))                                                               // two days only
        XCTAssertEqual(r.verdict, .notEnoughData)
        XCTAssertTrue(r.summary.contains("isn't enough logged"))
    }

    func testTheCurrentWeekSoFarIsMarkedAndCompared() {
        let r = review(data(), week: 16, today: 18)                                                  // Wednesday of that week
        XCTAssertFalse(r.isFullWeek); XCTAssertEqual(r.daysCovered, 3)
    }

    func testMeasurementsTakenOrNot() {
        var c = camp(); c.measureEveryDays = 14
        let taken = [MeasureEntry(day: day(2), values: [.navel: 85, .chest: 97]), MeasureEntry(day: day(16), values: [.navel: 83.5, .chest: 97])]
        let a = metric(review(data(), measurements: taken, c: c), "measurements")!
        XCTAssertTrue(a.value.hasPrefix("taken"))
        XCTAssertTrue(a.text.contains("Waist at the navel 83.5 cm") && a.text.contains("navel -1.5 cm"))
        let b = metric(review(data(), measurements: [MeasureEntry(day: day(2), values: [.navel: 85])], c: c), "measurements")!
        XCTAssertEqual(b.value, "not taken")
        XCTAssertTrue(b.text.contains("Not taken this week"))
        XCTAssertNil(metric(review(data()), "measurements"))                                         // off and none taken: no row
    }

    func testTheSundayCard() {
        XCTAssertTrue(ReviewRules.isLastDayOfWeek(day(22), calendar: cal))
        XCTAssertFalse(ReviewRules.isLastDayOfWeek(day(21), calendar: cal))
        XCTAssertFalse(ReviewRules.isLastDayOfWeek(day(23), calendar: cal))                          // Monday
    }
}
