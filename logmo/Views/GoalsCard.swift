import SwiftUI

/// The goals section of the Dashboard tab. For the campaign running today it is live: today's
/// daily goals and this week's calories, with a button to edit. For a past campaign it
/// summarises how that campaign's goals went.
struct GoalsCard: View {
    @Environment(\.theme) private var theme
    let campaign: CampaignInfo
    let snaps: [DaySnapshot]
    let timeline: GoalTimeline
    let onEdit: () -> Void

    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var live: Bool { CampaignRules.contains(campaign, day: today) }

    var body: some View {
        Card(title: live ? "Goals" : "Goals in this campaign") {
            Text(campaign.title).font(.caption).foregroundStyle(theme.muted)
            if live { liveBody } else { summaryBody }
        }
    }

    // MARK: Live

    @ViewBuilder private var liveBody: some View {
        let ws = Metrics.weekStart(of: today)
        let goals = timeline.goals(forDay: today)
        let todays = snaps.first { cal.isDate($0.date, inSameDayAs: today) }
        let status = Metrics.dayGoalStatus(todays, goals: goals)
        let week = Metrics.weekStatus(snaps, weekStart: ws, goals: timeline.goals(forWeekStarting: ws), today: today)

        if goals == nil {
            Text("No goals set for this campaign yet.").foregroundStyle(theme.muted)
        } else {
            Text("Today").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
            goalRow("Protein", value: todays?.proteinG, goal: goals?.proteinDaily, unit: "g", met: status.protein)
            goalRow("Steps", value: todays?.steps, goal: goals?.stepsDaily, unit: "", met: status.steps)
            goalRow("Water", value: todays?.waterMl, goal: goals?.waterDailyMl, unit: "ml", met: status.water)
            if !(goals?.hasDailyGoals ?? false) { Text("No daily goals set.").font(.caption).foregroundStyle(theme.muted) }

            Divider()
            Text("This week").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
            weekRow(week)
        }
        Button("Edit goals", action: onEdit).font(.subheadline)
    }

    private func goalRow(_ title: String, value: Int?, goal: Int?, unit: String, met: Bool?) -> some View {
        Group {
            if let goal {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                        Spacer()
                        Text("\((value ?? 0).formatted()) / \(goal.formatted()) \(unit)")
                            .font(.subheadline).monospacedDigit().foregroundStyle(theme.muted)
                        StatusIcon(ok: met == true ? true : nil)
                    }
                    ProgressView(value: min(Double(value ?? 0) / Double(max(goal, 1)), 1))
                        .tint(met == true ? theme.good : theme.accent)
                }
            }
        }
    }

    private func weekRow(_ w: WeekStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let goal = w.goal {
                HStack {
                    Text("Calories")
                    Spacer()
                    Text("avg \(Int((w.average ?? 0).rounded()).formatted()) / \(Int((w.dailyTarget ?? 0).rounded()).formatted()) kcal")
                        .font(.subheadline).monospacedDigit().foregroundStyle(theme.muted)
                    StatusIcon(ok: w.outcome == .met ? true : w.outcome == .missed ? false : nil)
                }
                ProgressView(value: min((w.average ?? 0) / max(w.dailyTarget ?? 1, 1), 1))
                    .tint(offTarget(w) ? theme.bad : (w.outcome == .met ? theme.good : theme.accent))
                Text(weekCaption(w, goal)).font(.caption).foregroundStyle(theme.muted)
            } else {
                Text("No weekly calorie goal set.").font(.caption).foregroundStyle(theme.muted)
            }
        }
    }

    /// Average currently on the wrong side of the daily-equivalent target.
    private func offTarget(_ w: WeekStatus) -> Bool {
        guard let avg = w.average, let target = w.dailyTarget else { return false }
        return w.atOrUnder ? avg > target : avg < target
    }

    private func weekCaption(_ w: WeekStatus, _ goal: Int) -> String {
        let days = "\(w.daysWithCalories) of 7 days logged"
        guard let avg = w.average, let target = w.dailyTarget else { return "No calories logged yet · \(days)" }
        let diff = Int(abs(avg - target).rounded())
        let side = w.atOrUnder ? (avg <= target ? "under" : "over") : (avg >= target ? "over" : "under")
        return "\(diff.formatted()) kcal/day \(side) target (\(goal.formatted()) ÷ 7) · \(days)"
    }

    // MARK: Past campaign

    private struct Summary {
        var daysWithGoals = 0, daysMet = 0, weeksMet = 0, weeksTotal = 0
        var last: GoalSet?
    }

    private func summary() -> Summary {
        var r = Summary()
        let end = min(campaign.end ?? today, today)
        let map = Dictionary(snaps.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        for d in Insights.days(from: campaign.start, to: end) {
            let goals = timeline.goals(forDay: d)
            guard goals?.hasDailyGoals == true else { continue }
            r.daysWithGoals += 1
            if Metrics.dayGoalStatus(map[d], goals: goals).allMet { r.daysMet += 1 }
        }
        // Finished weeks whose calorie goal belonged to this campaign.
        var ws = Metrics.weekStart(of: campaign.start)
        while cal.date(byAdding: .day, value: 6, to: ws)! <= end {
            if timeline.book?.owner(ofWeek: ws)?.id == campaign.id,
               let goals = timeline.goals(forWeekStarting: ws), goals.caloriesWeekly != nil {
                r.weeksTotal += 1
                if Metrics.weekStatus(snaps, weekStart: ws, goals: goals, today: today).outcome == .met { r.weeksMet += 1 }
            }
            ws = cal.date(byAdding: .day, value: 7, to: ws)!
        }
        r.last = timeline.goals(forDay: end)
        return r
    }

    @ViewBuilder private var summaryBody: some View {
        let r = summary()
        if r.daysWithGoals == 0 && r.weeksTotal == 0 {
            Text("No goals were set in this campaign.").foregroundStyle(theme.muted)
        } else {
            summaryLine("Daily goals met", r.daysWithGoals == 0 ? "—" : "\(r.daysMet) of \(r.daysWithGoals) days")
            summaryLine("Weekly calorie goal met", r.weeksTotal == 0 ? "—" : "\(r.weeksMet) of \(r.weeksTotal) finished weeks")
            if let last = r.last {
                Divider()
                Text("Goals at the end").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
                if let c = last.caloriesWeekly { summaryLine("Calories per week", "\(c.formatted()) kcal, \(last.caloriesAtOrUnder ? "at or under" : "at or over")") }
                if let p = last.proteinDaily { summaryLine("Protein per day", "\(p) g") }
                if let s = last.stepsDaily { summaryLine("Steps per day", s.formatted()) }
                if let w = last.waterDailyMl { summaryLine("Water per day", "\(w.formatted()) ml") }
            }
        }
    }

    private func summaryLine(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(theme.muted) }.font(.subheadline)
    }
}
