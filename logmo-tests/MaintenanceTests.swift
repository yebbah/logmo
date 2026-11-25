import XCTest
@testable import logmo

final class MaintenanceTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }()
    func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!)! }

    /// `n` days from 1 Sep. Weight falls by `perDay` kg a day from 80; calories are constant; either can be missing on some days.
    func log(_ n: Int, perDay: Double = 0, calories: Int? = 2400, weigh: (Int) -> Bool = { _ in true }, eat: (Int) -> Bool = { _ in true }) -> [DaySnapshot] {
        (0..<n).map { i in
            let w: Double? = weigh(i) ? 80 + perDay * Double(i) : nil
            let c: Int? = eat(i) ? calories : nil
            return DaySnapshot(date: day(i), weightKg: w, logged: [], calories: c)
        }
    }

    func testSteadyWeightMeansMaintenanceEqualsWhatYouEat() {
        let e = Maintenance.estimate(log(40), through: day(39), calendar: cal)!
        XCTAssertEqual(e.source, .trend); XCTAssertEqual(e.status, .updating); XCTAssertEqual(e.confidence, .high)
        XCTAssertEqual(Double(e.kcalPerDay), 2400, accuracy: 5)
    }

    func testLosingWeightMeansMaintenanceIsAboveWhatYouEat() {
        // 0.07 kg a day is 0.49 kg a week: about 540 kcal a day below maintenance.
        let e = Maintenance.estimate(log(60, perDay: -0.07), through: day(59), calendar: cal)!
        XCTAssertEqual(Double(e.kcalPerDay), 2400 + 0.49 * 1100, accuracy: 60)
    }

    func testGainingWeightMeansMaintenanceIsBelowWhatYouEat() {
        let e = Maintenance.estimate(log(60, perDay: 0.05, calories: 3000), through: day(59), calendar: cal)!
        XCTAssertEqual(Double(e.kcalPerDay), 3000 - 0.35 * 1100, accuracy: 60)
    }

    func testNothingIsEstimatedDuringTheFirstTenDays() {
        let s = Maintenance.series(log(10), through: day(9), calendar: cal)
        XCTAssertEqual(s.count, 10); XCTAssertTrue(s.allSatisfy { $0.tdee == nil })
        XCTAssertNil(Maintenance.estimate(log(10), through: day(9), calendar: cal))
        XCTAssertNotNil(Maintenance.series(log(14), through: day(13), calendar: cal).last?.tdee)
    }

    func testTheEstimateIsHeldWhileLogsAreTooThin() {
        // 30 good days, then ten days with weigh-ins on only two of them: the estimate holds and says so.
        let days = log(40, weigh: { $0 < 30 || $0 == 33 || $0 == 38 })
        let s = Maintenance.series(days, through: day(39), calendar: cal)
        XCTAssertEqual(s.last!.status, .waiting)
        XCTAssertEqual(s.last!.tdee!, s[29].tdee!, accuracy: 25)                        // carried, not rebuilt from nothing
        let e = Maintenance.estimate(days, through: day(39), calendar: cal)!
        XCTAssertEqual(e.status, .waiting); XCTAssertEqual(e.confidence, .low)
    }

    func testMissingCalorieDaysAreNeverTreatedAsZero() {
        let days = log(40, eat: { $0 % 3 != 0 })                                         // a third of the days have no calories
        let e = Maintenance.estimate(days, through: day(39), calendar: cal)!
        XCTAssertEqual(Double(e.kcalPerDay), 2400, accuracy: 10)                         // not dragged down by blanks
    }

    func testTooFewCalorieLogsHoldTheEstimate() {
        let days = log(40, eat: { $0 < 30 })                                             // none for the last ten days
        XCTAssertEqual(Maintenance.series(days, through: day(39), calendar: cal).last!.status, .waiting)
    }

    func testNoDataNoEstimate() {
        XCTAssertNil(Maintenance.estimate([], through: day(5), calendar: cal))
        XCTAssertNil(Maintenance.estimate(log(30, calories: nil), through: day(29), calendar: cal))        // weigh-ins alone can't give calories
    }

    // MARK: Formula

    func testFormulaEstimateFollowsMifflinStJeor() {
        let p = MaintenanceProfile(sex: .male, age: 30, heightCm: 180, activity: .moderate)
        let maleBMR: Double = 10 * 80 + 6.25 * 180 - 5 * 30 + 5          // 1,780
        XCTAssertEqual(Maintenance.formulaEstimate(p, weightKg: 80), Int((maleBMR * 1.55).rounded()))   // 2,759
        let f = MaintenanceProfile(sex: .female, age: 30, heightCm: 165, activity: .light)
        let femaleBMR: Double = 10 * 62 + 6.25 * 165 - 5 * 30 - 161
        XCTAssertEqual(Maintenance.formulaEstimate(f, weightKg: 62), Int((femaleBMR * 1.375).rounded()))
    }

    func testTheFormulaFillsInUntilTheLogsHaveBuiltAnEstimate() {
        let p = MaintenanceProfile(sex: .male, age: 30, heightCm: 180, activity: .moderate)
        let early = Maintenance.estimate(log(6), through: day(5), profile: p, calendar: cal)!
        XCTAssertEqual(early.source, .formula); XCTAssertEqual(early.confidence, .low); XCTAssertEqual(early.status, .waiting)
        let later = Maintenance.estimate(log(40), through: day(39), profile: p, calendar: cal)!
        XCTAssertEqual(later.source, .trend)
        XCTAssertNotNil(later.formulaKcal)                                               // kept beside it as a cross-check
        XCTAssertNil(Maintenance.estimate(log(6), through: day(5), calendar: cal))       // no profile, no data: nothing
    }

    func testProfileNeedsPlausibleValues() {
        let d = UserDefaults(suiteName: "maintenance-tests")!
        d.removePersistentDomain(forName: "maintenance-tests")
        XCTAssertNil(MaintenanceProfile.load(d))
        d.set("male", forKey: MaintenanceProfile.sexKey); d.set(30, forKey: MaintenanceProfile.ageKey); d.set(180.0, forKey: MaintenanceProfile.heightKey)
        XCTAssertEqual(MaintenanceProfile.load(d)?.activity, .light)                      // a default until chosen
        d.set(3, forKey: MaintenanceProfile.ageKey)
        XCTAssertNil(MaintenanceProfile.load(d))
        d.removePersistentDomain(forName: "maintenance-tests")
    }
}
