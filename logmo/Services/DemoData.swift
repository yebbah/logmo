#if DEBUG
import Foundation
import SwiftData

/// Debug-only sample data, enabled with the `-demo-data` launch argument.
/// Uses an in-memory store, so it never touches the real database.
enum DemoData {
    static var enabled: Bool { CommandLine.arguments.contains("-demo-data") }

    static func seed(_ context: ModelContext, days: Int = 56) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var seed: UInt64 = 42
        func rnd() -> Double {                      // deterministic 0..<1
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        func rating(_ base: Double) -> Int { min(5, max(1, Int((base + rnd() * 2 - 1).rounded()))) }

        for i in stride(from: days, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            if i % 9 == 4 { continue }              // a few unlogged days
            let log = DayLog(day: d)
            let progress = Double(days - i) / Double(days)
            if i % 5 != 2 { log.weightKg = 84.0 - 4.5 * progress + (rnd() - 0.5) * 1.2 }
            log.calories = 1800 + Int(rnd() * 500)
            log.proteinG = 110 + Int(rnd() * 70)
            log.fatG = 50 + Int(rnd() * 30)
            log.carbsG = 150 + Int(rnd() * 100)
            log.waterMl = 1500 + Int(rnd() * 1500)
            log.steps = 5000 + Int(rnd() * 8000)
            log.sleep = rating(3.5); log.fatigue = rating(2.5); log.stress = rating(2.8)
            log.hunger = rating(3); log.performance = rating(3.6)
            log.appetite = rating(3.2); log.soreness = rating(2.4)
            if i % 7 == 3 { log.soreness = nil }    // some incomplete check-ins
            context.insert(log)
        }
        if CommandLine.arguments.contains("-demo-long") {
            // Four campaigns, the current one being a default with a long name: #4 Maintenance (default).
            func d(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }
            context.insert(Campaign(CampaignInfo(number: 1, kind: .maintenance, isDefault: true, start: d(-days), end: d(-43))))
            context.insert(Campaign(CampaignInfo(number: 2, kind: .cut, targetWeightKg: 78, start: d(-42), plannedWeeks: 8, end: d(-29), endedEarly: true)))
            context.insert(Campaign(CampaignInfo(number: 3, kind: .bulk, start: d(-28), plannedWeeks: 2, end: d(-15))))
            context.insert(Campaign(CampaignInfo(number: 4, kind: .maintenance, isDefault: true, start: d(-14))))
        } else {
        // Campaign 1: default maintenance for the first 4 weeks; Campaign 2: an 8-week cut, still running.
        let cutStart = cal.date(byAdding: .day, value: -27, to: today)!
        context.insert(Campaign(CampaignInfo(number: 1, kind: .maintenance, isDefault: true,
                                             start: cal.date(byAdding: .day, value: -days, to: today)!,
                                             end: cal.date(byAdding: .day, value: -1, to: cutStart)!)))
        context.insert(Campaign(CampaignInfo(number: 2, kind: .cut, targetWeightKg: 78.0, start: cutStart, plannedWeeks: 8)))
        }
        try? context.save()
        let infos = (try? context.fetch(FetchDescriptor<Campaign>()))?.map(\.info) ?? []
        let thisWeek = Metrics.weekStart(of: today)
        for w in -6...0 {
            let ws = cal.date(byAdding: .day, value: 7 * w, to: thisWeek)!
            let g = WeekGoal(weekStart: ws, campaignID: GoalRules.assignedCampaign(for: ws, in: infos)?.id)
            g.caloriesWeekly = 14500; g.proteinDaily = 140; g.stepsDaily = 8000; g.waterDailyMl = 2200
            context.insert(g)
        }
        try? context.save()
    }
}
#endif
