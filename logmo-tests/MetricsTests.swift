import XCTest
@testable import logmo

final class MetricsTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: n))! }
    func snap(_ n: Int, w: Double? = nil, _ t: Set<Tracker> = [.food]) -> DaySnapshot {
        DaySnapshot(date: day(n), weightKg: w, logged: w == nil ? t : t.union([.weight]))
    }

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
    func testCompliance() {
        let days = [snap(24, w: 80), snap(22), snap(17)]
        let c = Metrics.compliance(days, today: day(24), windowDays: 7, calendar: cal)
        XCTAssertEqual(c.daysLogged, 2)           // 17th is outside the window
        XCTAssertEqual(c.perTracker[.weight], 1)
    }
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

    func testCSVExportBlanksAndOrder() {
        let rows = [
            ExportRow(day: day(2), weightKg: nil, calories: 2000, proteinG: nil, waterMl: 0, ratings: ["soreness": 4]),
            ExportRow(day: day(1), weightKg: 80.25, calories: nil, proteinG: 150, waterMl: nil, ratings: [:]),
        ]
        let lines = CSVExport.render(rows, calendar: cal).split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines[1], "2026-11-01,80.250,,150,,,,,,,,")
        XCTAssertEqual(lines[2], "2026-11-02,,2000,,0,,,,,,,4")
    }
}
