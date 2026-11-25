import XCTest
import SwiftData
@testable import logmo

@MainActor
final class DataResetTests: XCTestCase {
    func testDeleteAllLeavesOnlyAFreshDefaultCampaign() throws {
        let container = try ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        CampaignStore.ensureDefault(context)
        let log = DayLog(day: Date()); log.weightKg = 80; log.onPeriod = true
        context.insert(log)
        let campaignID = try context.fetch(FetchDescriptor<Campaign>())[0].id
        context.insert(WeekGoal(weekStart: Date(), campaignID: campaignID))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<DayLog>()).count, 1)
        XCTAssertGreaterThan(try context.fetch(FetchDescriptor<WeekGoal>()).count, 0)

        try DataReset.deleteAll(context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<DayLog>()).count, 0)
        let campaigns = try context.fetch(FetchDescriptor<Campaign>())
        XCTAssertEqual(campaigns.count, 1); XCTAssertTrue(campaigns[0].isDefault)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WeekGoal>()).allSatisfy { $0.campaignID == campaigns[0].id })
    }
}

@MainActor
final class BackupTests: XCTestCase {
    func testBackupRoundTripRestoresEverything() throws {
        let container = try ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        CampaignStore.ensureDefault(context)
        let campaign = try context.fetch(FetchDescriptor<Campaign>())[0]
        let log = DayLog(day: Date()); log.weightKg = 81.2; log.sleep = 4; log.performanceNA = true; log.onPeriod = true; log.isSick = true
        context.insert(log)
        let goal = WeekGoal(weekStart: Date(), campaignID: campaign.id); goal.stepsDaily = 9000; goal.confirmed = false
        context.insert(goal)
        try context.save()

        UserDefaults.standard.set("lb", forKey: SettingsKey.unit); UserDefaults.standard.set(true, forKey: SettingsKey.trackCycle)
        let data = try Backup.encode(try Backup.make(context))
        UserDefaults.standard.set("kg", forKey: SettingsKey.unit); UserDefaults.standard.set(false, forKey: SettingsKey.trackCycle)
        try DataReset.deleteAll(context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DayLog>()).count, 0)

        try Backup.restore(try Backup.decode(data), into: context)
        let logs = try context.fetch(FetchDescriptor<DayLog>())
        XCTAssertEqual(logs.count, 1); XCTAssertEqual(logs[0].weightKg, 81.2); XCTAssertEqual(logs[0].sleep, 4)
        XCTAssertTrue(logs[0].performanceNA); XCTAssertEqual(logs[0].onPeriod, true); XCTAssertEqual(logs[0].isSick, true)
        let goals = try context.fetch(FetchDescriptor<WeekGoal>())
        XCTAssertEqual(goals.count, 1); XCTAssertEqual(goals[0].stepsDaily, 9000); XCTAssertFalse(goals[0].confirmed)
        XCTAssertEqual(goals[0].campaignID, campaign.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Campaign>()).map(\.id), [campaign.id])
        XCTAssertEqual(UserDefaults.standard.string(forKey: SettingsKey.unit), "lb")        // settings come back too
        XCTAssertTrue(UserDefaults.standard.bool(forKey: SettingsKey.trackCycle))
        UserDefaults.standard.set("kg", forKey: SettingsKey.unit); UserDefaults.standard.set(false, forKey: SettingsKey.trackCycle)
    }
}
