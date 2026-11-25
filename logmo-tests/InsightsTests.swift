import XCTest
@testable import logmo

final class InsightsTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }
    func snap(_ n: Int, kcal: Int? = nil, protein: Int? = nil, steps: Int? = nil, ratings: [String: Int] = [:], w: Double? = nil) -> DaySnapshot {
        DaySnapshot(date: day(n), weightKg: w, logged: [.food], calories: kcal, proteinG: protein, steps: steps, ratings: ratings)
    }

    func testAveragesIgnoreMissingDaysAndWindow() {
        let s = [snap(1, kcal: 2000, steps: 10000), snap(2, kcal: 1000), snap(3), snap(9, kcal: 9999)]
        let a = Insights.averages(s, from: day(1), to: day(5), calendar: cal)
        XCTAssertEqual(a.calories, 1500)            // 9th is outside; the unlogged 3rd isn't a zero
        XCTAssertEqual(a.steps, 10000)
        XCTAssertNil(a.proteinG)                    // nothing logged = unavailable, not 0
    }
    func testRatingSeriesKeepsGaps() {
        let s = [snap(1, ratings: ["sleep": 4]), snap(3, ratings: ["sleep": 2])]
        let series = Insights.ratingSeries(s, rating: "sleep", from: day(1), to: day(4), calendar: cal)
        XCTAssertEqual(series.map { $0.value }, [4, nil, 2, nil])
        XCTAssertEqual(Insights.average(series.map { $0.value }), 3)
        XCTAssertNil(Insights.average([nil, nil]))
    }
    func testBetterDirections() {
        XCTAssertEqual(Rating.sleep.betterWhen, .higher)
        XCTAssertEqual(Rating.performance.betterWhen, .higher)
        for r in [Rating.fatigue, .stress, .hunger, .soreness] { XCTAssertEqual(r.betterWhen, .lower) }
        XCTAssertEqual(Rating.appetite.betterWhen, .neutral)
    }
    func testProteinDays() {
        let t = GoalTimeline(byWeek: [day(2): GoalSet(proteinDaily: 140)])
        let s = [snap(2, protein: 150), snap(3, protein: 139), snap(4, protein: 140)]       // 5th unlogged
        let r = Insights.proteinDays(s, timeline: t, from: day(2), to: day(5), calendar: cal)
        XCTAssertEqual(r.hit, 2); XCTAssertEqual(r.missed, 2)
        let none = Insights.proteinDays(s, timeline: GoalTimeline(), from: day(2), to: day(5), calendar: cal)
        XCTAssertEqual(none.hit + none.missed, 0)                                            // no goal: nothing to hit
    }
    func testRateOfChange() {
        let days = (1...10).map { snap($0, w: 80 - Double($0) * 0.1) }     // falls 0.1 kg/day in raw weights
        let trend = Metrics.weightTrend(days, through: day(10), smoothingDays: 1, calendar: cal)
        let roc = Insights.rateOfChange(trend, calendar: cal)
        XCTAssertEqual(roc.count, 3)                                       // needs 7 earlier days of trend
        XCTAssertEqual(roc.first!.kgPerWeek, -0.7, accuracy: 1e-9)
        XCTAssertEqual(roc.first!.date, day(8))
    }
}

final class AppInfoTests: XCTestCase {
    func testContactEmailIsPreparedWithVersionsOnly() {
        let url = AppInfo.contactURL(versionString: "1.0.0 (1)", osVersion: "27.2")
        let c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(c.scheme, "mailto")
        XCTAssertEqual(c.path, "connectwithsvetlanamae@gmail.com")
        XCTAssertEqual(c.queryItems?.first { $0.name == "subject" }?.value, "logmo 1.0.0 (1) feedback")
        let body = c.queryItems?.first { $0.name == "body" }?.value ?? ""
        XCTAssertTrue(body.contains("logmo 1.0.0 (1), iOS 27.2"))
        XCTAssertFalse(body.lowercased().contains("kg"))                    // nothing from the user's data
    }
    func testBuiltBundleHasAVersion() {
        XCTAssertNotEqual(AppInfo.version, "?")
        XCTAssertNotEqual(AppInfo.build, "?")
    }
}
