import XCTest
import SwiftData
@testable import logmo

final class StartWeightTrendTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n - 1, to: cal.date(from: DateComponents(year: 2025, month: 11, day: 30))!)! }   // day 1 = 30 Nov 2025

    /// The sheet from the screenshot: weigh-ins of 55.80, 55.10, 55.50 and 55.80 on days 2, 3, 5 and 18; day 1 blank.
    func sheetDays() -> [DaySnapshot] {
        [(2, 55.8), (3, 55.1), (5, 55.5), (18, 55.8)].map { DaySnapshot(date: day($0.0), weightKg: $0.1, logged: []) }
    }

    func testAStartingWeightReproducesTheSheetsTrend() {
        let t = Metrics.weightTrend(sheetDays(), through: day(21), smoothingDays: 20, seeds: [day(1): 55.5], calendar: cal)
        func trend(_ n: Int) -> Double { t.first { $0.date == day(n) }!.trendKg }
        XCTAssertEqual(String(format: "%.2f", trend(7)), "55.49")           // Wk 1
        XCTAssertEqual(String(format: "%.2f", trend(14)), "55.49")          // Wk 2
        XCTAssertEqual(String(format: "%.2f", trend(21)), "55.52")          // Wk 3
    }

    func testWithoutOneTheTrendStartsAtTheFirstWeighIn_asBefore() {
        let t = Metrics.weightTrend(sheetDays(), through: day(21), smoothingDays: 20, calendar: cal)
        XCTAssertEqual(t.first!.date, day(2)); XCTAssertEqual(t.first!.trendKg, 55.8, accuracy: 1e-9)
        XCTAssertEqual(t.last!.trendKg, 55.72, accuracy: 0.01)
    }

    func testTheStartingWeightIsAlwaysUsed_aWeighInOnTheStartDayMovesItLikeAnyOther() {
        var days = sheetDays(); days.append(DaySnapshot(date: day(1), weightKg: 56.0, logged: []))
        let t = Metrics.weightTrend(days, through: day(3), smoothingDays: 20, seeds: [day(1): 55.5], calendar: cal)
        let a = 2.0 / 21
        XCTAssertEqual(t.first!.trendKg, a * 56.0 + (1 - a) * 55.5, accuracy: 1e-9)       // not 56.0 (the weigh-in) and not 55.5 (untouched)
    }

    func testTheTrendStartsAfreshOnEachCampaignsFirstDay() {
        let a = 2.0 / 21
        // 55.5 for the first campaign, then a second begins on day 11 from 52.0 while the weigh-ins are still near 55.
        let days = (1...20).map { DaySnapshot(date: day($0), weightKg: 55.5, logged: []) }
        let t = Metrics.weightTrend(days, through: day(20), smoothingDays: 20, seeds: [day(1): 55.5, day(11): 52.0], calendar: cal)
        XCTAssertEqual(t.first { $0.date == day(10) }!.trendKg, 55.5, accuracy: 1e-9)
        XCTAssertEqual(t.first { $0.date == day(11) }!.trendKg, a * 55.5 + (1 - a) * 52.0, accuracy: 1e-9)    // starts from 52, the day's weigh-in moves it
        // with no weigh-in on the start day the seed itself is the trend
        let gap = days.filter { $0.date != day(11) }
        let g = Metrics.weightTrend(gap, through: day(12), smoothingDays: 20, seeds: [day(1): 55.5, day(11): 52.0], calendar: cal)
        XCTAssertEqual(g.first { $0.date == day(11) }!.trendKg, 52.0, accuracy: 1e-9)
        XCTAssertGreaterThan(g.first { $0.date == day(12) }!.trendKg, 52.0)                // then it smooths toward the weigh-ins
    }

    func testOnlyRealCampaignsWithAStartingWeightSeedTheTrend() {
        let real = CampaignInfo(number: 2, kind: .cut, start: day(11), plannedWeeks: 8, startWeightKg: 55.5)
        let legacy = CampaignInfo(number: 3, kind: .bulk, start: day(40), plannedWeeks: 8)
        let auto = CampaignInfo(number: 1, kind: .maintenance, isDefault: true, start: day(1), startWeightKg: 99)
        XCTAssertEqual(CampaignRules.trendSeeds([real, legacy, auto], calendar: cal), [day(11): 55.5])
    }

    func testTheSuggestedStartingWeightIsTheCurrentTrend() {
        let days = (1...20).map { DaySnapshot(date: day($0), weightKg: 60 - 0.1 * Double($0), logged: []) }
        let s = CampaignRules.suggestedStartWeight(snaps: days, campaigns: [], smoothingDays: 16, today: day(20), calendar: cal)!
        XCTAssertEqual(s, (Metrics.weightTrend(days, through: day(20), smoothingDays: 16, calendar: cal).last!.trendKg * 10).rounded() / 10, accuracy: 1e-9)
        XCTAssertNil(CampaignRules.suggestedStartWeight(snaps: [], campaigns: [], smoothingDays: 16, today: day(20), calendar: cal))
    }

    func testPlausibleStartingWeights() {
        XCTAssertTrue(CampaignRules.isPlausibleStartWeight(55.5)); XCTAssertFalse(CampaignRules.isPlausibleStartWeight(5))
        XCTAssertFalse(CampaignRules.isPlausibleStartWeight(nil)); XCTAssertFalse(CampaignRules.isPlausibleStartWeight(900))
    }
}

final class MaintenanceAcrossCampaignsTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!)! }
    func log(_ n: Int) -> [DaySnapshot] { (0..<n).map { DaySnapshot(date: day($0), weightKg: 80 - 0.03 * Double($0), logged: [], calories: 2400) } }

    func testANewCampaignContinuingFromAnEarlierOneHasAnEstimateImmediately() {
        // 60 days of logging, a second campaign beginning on day 50 from the current trend: the estimate does not start over.
        let days = log(60)
        let carry = Metrics.weightTrend(days, through: day(49), smoothingDays: 16, calendar: cal).last!.trendKg
        let seeds = [day(0): 80.0, day(50): (carry * 10).rounded() / 10]
        let s = Maintenance.series(days, through: day(59), seeds: seeds, calendar: cal)
        XCTAssertNotNil(s[50].tdee); XCTAssertNotNil(s[52].tdee)                          // right from the campaign's first days
        XCTAssertEqual(s[55].tdee!, s[45].tdee!, accuracy: 120)                           // and carried on, not reset
        XCTAssertNotNil(Maintenance.estimate(days, through: day(51), seeds: seeds, calendar: cal))
    }

    func testAStartThatMatchesTheTrendDoesNotHoldTheEstimateUp() {
        let days = log(60)
        let carry = Metrics.weightTrend(days, through: day(49), smoothingDays: 16, calendar: cal).last!.trendKg
        let continuing = Maintenance.series(days, through: day(59), seeds: [day(50): carry], calendar: cal)
        let plain = Maintenance.series(days, through: day(59), calendar: cal)
        XCTAssertEqual(continuing[53].tdee!, plain[53].tdee!, accuracy: 25)               // the weekly change is read across the boundary
    }

    func testAStartThatJumpsHoldsTheEstimateForTheFirstWeekOnly() {
        let days = log(60)
        let jump = Maintenance.series(days, through: day(59), seeds: [day(50): 70.0], calendar: cal)      // an abrupt reset 10 kg lower
        XCTAssertEqual(jump[54].tdee!, jump[49].tdee!, accuracy: 1e-9)                    // carried, not thrown off by a false 10 kg loss
        XCTAssertNotEqual(jump[58].tdee!, jump[49].tdee!)                                 // moves again once a week of the new trend exists
    }

    func testTheFirstFourWeeksAreCountedFromTheFirstLogNotFromACampaign() {
        let early = Maintenance.series(log(27), through: day(26), seeds: [day(20): 79.0], calendar: cal)   // a campaign began on day 20
        XCTAssertTrue(early.allSatisfy { $0.tdee == nil })
    }
}

@MainActor
final class StartWeightStoreTests: XCTestCase {
    var container: ModelContainer?
    func makeContext() throws -> ModelContext {
        let c = try ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container = c; return c.mainContext
    }
    var today: Date { Calendar.current.startOfDay(for: Date()) }

    func testARealCampaignCannotStartWithoutAStartingWeight() throws {
        let context = try makeContext()
        for bad in [nil, 5.0, 900.0] as [Double?] {
            if case .failure(let e) = CampaignStore.start(context, kind: .cut, targetKg: nil, start: today, weeks: 8, startWeightKg: bad) { XCTAssertEqual(e, .invalidStartWeight) }
            else { XCTFail("accepted \\(String(describing: bad))") }
        }
        XCTAssertTrue(CampaignStore.all(context).filter { !$0.isDefault }.isEmpty)
        if case .failure = CampaignStore.start(context, kind: .cut, targetKg: nil, start: today, weeks: 8, startWeightKg: 55.5) { XCTFail("refused a good one") }
        XCTAssertEqual(CampaignStore.all(context).first { !$0.isDefault }?.startWeightKg, 55.5)
    }

    func testTheStartingWeightCanBeSetOnARunningCampaignButNotAPastOne() throws {
        let context = try makeContext()
        let running = Campaign(CampaignInfo(number: 1, kind: .cut, start: today, plannedWeeks: 8))
        let past = Campaign(CampaignInfo(number: 2, kind: .cut, start: Calendar.current.date(byAdding: .day, value: -60, to: today)!, plannedWeeks: 4,
                                         end: Calendar.current.date(byAdding: .day, value: -32, to: today)!, startWeightKg: 60))
        context.insert(running); context.insert(past)
        if case .failure = CampaignStore.setStartWeight(context, running, kg: 55.5) { XCTFail("a running campaign can be set") }
        XCTAssertEqual(running.startWeightKg, 55.5)
        if case .success = CampaignStore.setStartWeight(context, past, kg: 50) { XCTFail("a past campaign is read-only") }
        XCTAssertEqual(past.startWeightKg, 60)
        if case .success = CampaignStore.setStartWeight(context, running, kg: 3) { XCTFail("implausible") }
    }

    func testTheStartingWeightSurvivesBackupAndAppearsInTheCampaignExport() throws {
        let context = try makeContext()
        CampaignStore.start(context, kind: .cut, targetKg: 50, start: today, weeks: 8, startWeightKg: 55.5)
        let data = try Backup.encode(try Backup.make(context))
        try DataReset.deleteAll(context)
        try Backup.restore(try Backup.decode(data), into: context)
        let c = CampaignStore.all(context).first { !$0.isDefault }!
        XCTAssertEqual(c.startWeightKg, 55.5)
        XCTAssertTrue(CSVExport.campaignsCSV([c.info]).contains(",55.5,"))
    }

    func testEditingAnUpcomingCampaignCanChangeItsStartingWeight() throws {
        let context = try makeContext()
        let later = Calendar.current.date(byAdding: .day, value: 5, to: today)!
        CampaignStore.start(context, kind: .cut, targetKg: nil, start: later, weeks: 4, startWeightKg: 55.5)
        let u = CampaignStore.upcoming(context)!
        let r = CampaignStore.reschedule(context, u, start: later, weeks: 4, startWeightKg: 56.2)
        if case .failure = r { XCTFail("refused") }
        XCTAssertEqual(u.startWeightKg, 56.2)
        if case .success = CampaignStore.reschedule(context, u, start: later, weeks: 4, startWeightKg: 2) { XCTFail("accepted 2 kg") }
    }
}

final class WeeklyRateAndWeekHeadlineTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }()
    func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n - 1, to: cal.date(from: DateComponents(year: 2025, month: 12, day: 1))!)! }    // day 1 = Monday 1 Dec 2025

    /// The workbook's example moved to start on a Monday: weigh-ins of 55.8, 55.1, 55.5 and 55.8 on days 2, 3, 5 and 18, trend seeded at 55.5.
    func trend() -> [TrendPoint] {
        let days = [(2, 55.8), (3, 55.1), (5, 55.5), (18, 55.8)].map { DaySnapshot(date: day($0.0), weightKg: $0.1, logged: []) }
        return Metrics.weightTrend(days, through: day(21), smoothingDays: 20, seeds: [day(1): 55.5], calendar: cal)
    }

    func testWeeklyRowsGiveEachWeeksTrendAndItsChangeFromTheWeekBefore() {
        let rows = Metrics.weeklyTrendRows(trend(), from: day(1), through: day(21), calendar: cal)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map(\.weekStart), [day(15), day(8), day(1)])                 // newest first
        XCTAssertEqual(String(format: "%.2f", rows[2].trendKg), "55.49")                 // week 1, as in the workbook
        XCTAssertNil(rows[2].changeKg)                                                   // nothing before it: N/A
        XCTAssertEqual(rows[1].changeKg!, 0, accuracy: 1e-9)                             // week 2: no weigh-ins, the trend holds
        XCTAssertEqual(String(format: "%.2f", rows[0].trendKg), "55.52")                 // week 3, as in the workbook
        XCTAssertEqual(rows[0].changeKg!, 0.03, accuracy: 0.005)                         // "0.03 kg"
        XCTAssertEqual(rows[0].changePercent!, 0.05, accuracy: 0.01)                     // "or 0.05%"
        XCTAssertTrue(rows.allSatisfy { !$0.inProgress })
    }

    func testTheWeekInProgressIsMarkedAndUsesTheDaysSoFar() {
        let rows = Metrics.weeklyTrendRows(trend(), from: day(1), through: day(18), calendar: cal)      // day 18 is a Wednesday
        XCTAssertTrue(rows[0].inProgress); XCTAssertEqual(rows[0].endDay, day(18))
        XCTAssertEqual(Metrics.weeklyTrendRows(trend(), from: day(1), through: day(21), limit: 2, calendar: cal).count, 2)
        XCTAssertTrue(Metrics.weeklyTrendRows([], from: day(1), through: day(21), calendar: cal).isEmpty)
    }

    func testTheWeekHeadlineSaysWhichWeekOfTheCampaign() {
        let c = CampaignInfo(number: 2, kind: .cut, start: day(1), plannedWeeks: 8)
        let h = CampaignRules.weekHeadline([c], today: day(10), calendar: cal)              // Wednesday of the second week
        XCTAssertEqual(h.title, "Week 2 of 8")
        XCTAssertTrue(h.dates.contains("8 Dec") || h.dates.contains("Dec 8"), h.dates)
        let none = CampaignRules.weekHeadline([], today: day(10), calendar: cal)
        XCTAssertEqual(none.title, "This week")
        let past = CampaignInfo(number: 1, kind: .cut, start: day(1), plannedWeeks: 2)      // over by day 20
        XCTAssertEqual(CampaignRules.weekHeadline([past], today: day(20), calendar: cal).title, "This week")
    }
}

final class RateOfChangeAcrossARestartTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }()
    func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n - 1, to: cal.date(from: DateComponents(year: 2026, month: 11, day: 2))!)! }     // day 1 = Mon 2 Nov

    /// The reported case: weigh-ins around 55 before a one-week campaign (days 22 to 28) that starts at 55.8 with nothing logged in it.
    func scenario() -> [TrendPoint] {
        let days = (1...21).filter { $0 % 3 == 0 }.map { DaySnapshot(date: day($0), weightKg: 55.0, logged: []) }
        return Metrics.weightTrend(days, through: day(28), smoothingDays: 20, seeds: [day(22): 55.8], calendar: cal)
    }

    func testTheSeedLandingFarFromTheOldTrendIsMarkedARestart() {
        let t = scenario()
        XCTAssertTrue(t.first { $0.date == day(22) }!.restart)
        XCTAssertEqual(t.first { $0.date == day(22) }!.trendKg, 55.8, accuracy: 1e-9)
        XCTAssertEqual(t.filter(\.restart).count, 1)
    }

    func testTheWeeklyRowForTheRestartWeekIsNotAChange() {
        let rows = Metrics.weeklyTrendRows(scenario(), from: day(22), through: day(28), calendar: cal)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].trendKg, 55.8, accuracy: 1e-9)
        XCTAssertNil(rows[0].changeKg)                                                    // N/A, not +0.8 kg
        XCTAssertNil(rows[0].changePercent)
    }

    func testTheDailyAndSevenDayChangesAreBlankAcrossTheRestart() {
        let t = scenario()
        let rates = Insights.rateOfChange(t, calendar: cal).filter { $0.date >= day(22) && $0.date <= day(28) }
        XCTAssertTrue(rates.isEmpty)                                                      // every day of the week reaches back across the restart
        XCTAssertNil(Metrics.trendChange(t.filter { $0.date >= day(10) }, overDays: 7, calendar: cal))
        XCTAssertNotNil(Metrics.trendChange(t.filter { $0.date <= day(21) }, overDays: 7, calendar: cal))     // before it, changes work as usual
    }

    func testTheWeekAfterTheRestartIsComparedWithTheNewTrend() {
        let days = (1...21).filter { $0 % 3 == 0 }.map { DaySnapshot(date: day($0), weightKg: 55.0, logged: []) }
            + [DaySnapshot(date: day(30), weightKg: 55.4, logged: [])]
        let t = Metrics.weightTrend(days, through: day(35), smoothingDays: 20, seeds: [day(22): 55.8], calendar: cal)
        let rows = Metrics.weeklyTrendRows(t, from: day(22), through: day(35), calendar: cal)
        XCTAssertEqual(rows.count, 2)
        XCTAssertNil(rows[1].changeKg)                                                    // the campaign's first week
        XCTAssertNotNil(rows[0].changeKg); XCTAssertEqual(rows[0].changeKg!, rows[0].trendKg - 55.8, accuracy: 1e-9)    // the next week moves from 55.8
    }

    func testAStartingWeightThatMatchesTheTrendIsNotARestart() {
        let days = (1...30).map { DaySnapshot(date: day($0), weightKg: 55.0, logged: []) }
        let t = Metrics.weightTrend(days, through: day(30), smoothingDays: 20, seeds: [day(22): 55.0], calendar: cal)
        XCTAssertTrue(t.allSatisfy { !$0.restart })
        XCTAssertNotNil(Metrics.weeklyTrendRows(t, from: day(1), through: day(30), calendar: cal).first?.changeKg)
    }
}
