import XCTest
@testable import logmo

extension WeekSuggestionTests {
    private var profile: MaintenanceProfile { MaintenanceProfile(sex: .male, age: 35, heightCm: 178, activity: .moderate) }   // about 2,700 kcal

    private func paced(_ kind: CampaignKind, _ snaps: [DaySnapshot], profile p: MaintenanceProfile? = nil, pace: SuggestionPace = .conservative,
                       measurements: [MeasureEntry] = [], goals g: GoalSet? = nil) -> WeekSummary {
        let c = CampaignInfo(number: 1, kind: kind, targetWeightKg: kind == .cut ? 76 : nil, start: day(2), plannedWeeks: 12)
        return SuggestionRules.summary(campaign: c, snaps: snaps, current: g ?? goals, window: .thisWeekSoFar, includeCycle: true, includeSick: true,
                                       today: day(22), profile: p, pace: pace, measurements: measurements, calendar: cal)
    }

    func testACutOffersAFasterPaceBelowTheConservativeOne() {
        let o = SuggestionRules.options(paced(.cut, data(), profile: profile))
        let agg = try! XCTUnwrap(o.aggressive)
        XCTAssertLessThan(agg.caloriesPerDay, o.conservative.caloriesPerDay)
        XCTAssertGreaterThanOrEqual(agg.caloriesPerDay, 1200)
        XCTAssertGreaterThanOrEqual(Double(agg.caloriesPerDay), 0.75 * 2700 - 60)                 // never more than a quarter below maintenance
        XCTAssertGreaterThanOrEqual(o.conservative.caloriesPerDay - agg.caloriesPerDay, 0)
        XCTAssertLessThanOrEqual(2100 - agg.caloriesPerDay, SuggestionRules.aggressiveStepLimit)   // one week's move is limited
        XCTAssertEqual(agg.pace, .aggressive); XCTAssertEqual(o.conservative.pace, .conservative)
        XCTAssertLessThan(agg.expectedKgPerWeek!, o.conservative.expectedKgPerWeek!)
    }

    func testThePreferredPaceDecidesTheLeadingSuggestion() {
        let s = paced(.cut, data(), profile: profile, pace: .aggressive)
        let o = SuggestionRules.options(s)
        XCTAssertEqual(SuggestionRules.baseline(s).caloriesPerDay, o.aggressive!.caloriesPerDay)
    }

    func testNoFasterPaceWithoutAnEstimateOfMaintenanceOrOnMaintenanceOrWhenSick() {
        XCTAssertNil(SuggestionRules.options(paced(.cut, data())).aggressive)                                  // no profile, under four weeks of logs
        XCTAssertTrue(SuggestionRules.options(paced(.cut, data())).aggressiveNote!.contains("maintenance"))
        let m = SuggestionRules.options(paced(.maintenance, data(weightPerDay: 0), profile: profile))
        XCTAssertNil(m.aggressive); XCTAssertTrue(m.aggressiveNote!.contains("one pace"))
        let sick = SuggestionRules.options(paced(.cut, data(sick: [20, 21]), profile: profile))
        XCTAssertNil(sick.aggressive); XCTAssertTrue(sick.aggressiveNote!.contains("sick"))
    }

    func testWhyIsPlainLanguageAndMentionsMeasurementsAsASecondOpinion() {
        let ms = [MeasureEntry(day: day(3), values: [.navel: 85.0, .chest: 97, .biceps: 33]), MeasureEntry(day: day(17), values: [.navel: 83.5, .chest: 97, .biceps: 33])]
        let p = SuggestionRules.baseline(paced(.cut, data(), profile: profile, measurements: ms))
        let why = p.why.map(\.text).joined(separator: " ")
        XCTAssertTrue(why.contains("down about 0.49 kg a week"))
        XCTAssertTrue(why.contains("waist at the navel is down 1.5 cm over 14 days"))
        XCTAssertTrue(why.contains("fat rather than muscle"))
        XCTAssertTrue(why.contains("never change goals on their own"))
        XCTAssertTrue(why.contains("above your target"))                                                  // 76 kg target
        XCTAssertFalse(p.why.isEmpty)
    }

    func testAWaistThatGrowsOnACutIsFlaggedNotCelebrated() {
        let ms = [MeasureEntry(day: day(3), values: [.navel: 85.0]), MeasureEntry(day: day(17), values: [.navel: 86.5])]
        let p = SuggestionRules.baseline(paced(.cut, data(), measurements: ms))
        XCTAssertTrue(p.why.contains { $0.kind == .warn && $0.text.contains("waist at the navel is up 1.5 cm") })
    }

    func testMeasurementsNeverMoveTheGoalsOnTheirOwn() {
        let ms = [MeasureEntry(day: day(3), values: [.navel: 85.0]), MeasureEntry(day: day(17), values: [.navel: 86.5])]
        XCTAssertEqual(SuggestionRules.baseline(paced(.cut, data(), measurements: ms)).caloriesPerDay,
                       SuggestionRules.baseline(paced(.cut, data())).caloriesPerDay)
    }
}
