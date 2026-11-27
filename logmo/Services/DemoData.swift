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
            if i % 3 == 0 { log.performance = nil; log.performanceNA = true }   // rest days
            log.onPeriod = (i % 28 >= 3 && i % 28 <= 7) ? true : (i % 4 == 0 ? false : nil)   // used when cycle tracking is on
            if i % 3 == 0 {                         // body composition readings from Health, every third day
                log.healthBodyFat = 20.4 - 2.1 * progress + (rnd() - 0.5) * 0.3
                log.healthLeanKg = 63.0 + 0.5 * progress + (rnd() - 0.5) * 0.2
            }
            log.healthSleepMinutes = 380 + Int(rnd() * 90); log.healthRestingHR = 55 + Int(rnd() * 5); log.healthHRV = 44 + Int(rnd() * 10)
            if i == 0 {                             // today: some values from Health, one typed over, and a workout to ask about
                log.imported = [.steps, .calories, .protein, .carbs, .fat, .water, .sleep]
                log.healthSleepMinutes = 166; log.healthSleepAwakeMinutes = 25; log.healthSleepDeepMinutes = 25; log.healthSleepREMMinutes = 35; log.sleep = 1
                log.overridden = [.weight]
                log.healthWorkoutMinutes = 52
                log.performance = nil; log.performanceNA = false
            }
            if let step = [27: 0.0, 20: 1.0, 12: 2.0][i] {       // measurements every week from the cut's start: the next one is due now
                log.measures = BodyMeasures(values: [.navel: 85.0 - 0.75 * step, .belowNavel: 94.0 - 0.3 * step, .aboveNavel: 79.0 - 0.5 * step,
                                                     .chest: 97.0, .thighs: 58.0 - 0.25 * step, .calves: 37.0, .biceps: 32.5 + 0.25 * step])
            }
            context.insert(log)
        }
        if CommandLine.arguments.contains("-demo-long") {
            // Four campaigns, the current one a maintenance campaign with an explicit end.
            func d(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }
            context.insert(Campaign(CampaignInfo(number: 1, kind: .maintenance, isDefault: true, start: d(-days), end: d(-43))))
            context.insert(Campaign(CampaignInfo(number: 2, kind: .cut, targetWeightKg: 78, start: d(-42), plannedWeeks: 8, end: d(-29), endedEarly: true)))
            context.insert(Campaign(CampaignInfo(number: 3, kind: .bulk, start: d(-28), plannedWeeks: 2, end: d(-15))))
            context.insert(Campaign(CampaignInfo(number: 4, kind: .maintenance, start: d(-14), plannedWeeks: 8, startWeightKg: 80)))
        } else if CommandLine.arguments.contains("-demo-upcoming") {
            // A cut planned to start in ten days; the maintenance campaign before it has its own end.
            func d(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }
            context.insert(Campaign(CampaignInfo(number: 1, kind: .maintenance, isDefault: true, start: d(-days), end: d(9))))
            context.insert(Campaign(CampaignInfo(number: 2, kind: .cut, targetWeightKg: 78, start: d(10), plannedWeeks: 8)))
        } else {
        // Campaign 1: default maintenance for the first 4 weeks; Campaign 2: an 8-week cut, still running.
        let cutStart = cal.date(byAdding: .day, value: -27, to: today)!
        context.insert(Campaign(CampaignInfo(number: 1, kind: .maintenance, isDefault: true,
                                             start: cal.date(byAdding: .day, value: -days, to: today)!,
                                             end: cal.date(byAdding: .day, value: -1, to: cutStart)!)))
        context.insert(Campaign(CampaignInfo(number: 2, kind: .cut, targetWeightKg: 78.0, start: cutStart, plannedWeeks: 8,
                                             label: CommandLine.arguments.contains("-demo-label") ? "Summer cut" : nil, measureEveryDays: 7)))
        }
        try? context.save()
        let infos = (try? context.fetch(FetchDescriptor<Campaign>()))?.map(\.info) ?? []
        let thisWeek = Metrics.weekStart(of: today)
        for w in -6...0 {
            let ws = cal.date(byAdding: .day, value: 7 * w, to: thisWeek)!
            let g = WeekGoal(weekStart: ws, campaignID: GoalRules.assignedCampaign(for: ws, in: infos)?.id)
            g.caloriesWeekly = 14500; g.proteinDaily = 140; g.stepsDaily = 8000; g.waterDailyMl = 2200
            g.workoutDaysWeekly = 4
            if w == 0 && CommandLine.arguments.contains("-demo-carried") { g.confirmed = false }   // this week only carried over
            context.insert(g)
        }
        try? context.save()
    }
}
#endif
