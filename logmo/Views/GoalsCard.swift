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
    private var upcoming: Bool { CampaignRules.isUpcoming(campaign, today: today) }

    var body: some View {
        Card(title: live ? "Goals" : (upcoming ? "Goals for this campaign" : "Goals in this campaign")) {
            Text(CampaignRules.titleWithPeriod(campaign, today: today)).font(.caption).foregroundStyle(theme.muted)
            if live { liveBody } else if upcoming { upcomingBody } else { summaryBody }
        }
    }

    // MARK: Upcoming

    @ViewBuilder private var upcomingBody: some View {
        if let g = timeline.goals(forDay: campaign.start) {
            if let c = g.caloriesWeekly { summaryLine("Calories per day (weekly average)", "\((Double(c) / 7).rounded().formatted()) kcal, \(g.caloriesAtOrUnder ? "at or under" : "at or over")") }
            if let p = g.proteinDaily { summaryLine("Protein per day", "\(p) g") }
            if let s = g.stepsDaily { summaryLine(g.stepsIsWeeklyAverage ? "Steps, weekly average" : "Steps per day", s.formatted()) }
            if let w = g.waterDailyMl { summaryLine("Water per day", "\(w.formatted()) ml") }
            if let n = g.workoutDaysWeekly { summaryLine("Workout days per week", "\(n)") }
        } else {
            Text("No goals yet for this campaign.").foregroundStyle(theme.muted)
        }
        Text("They start as a copy of your latest goals and take effect when the campaign starts.")
            .font(.caption).foregroundStyle(theme.muted)
        Button("Edit goals", action: onEdit).font(.subheadline)
    }

    // MARK: Live

    @ViewBuilder private var liveBody: some View {
        let ws = Metrics.weekStart(of: today)
        let goals = timeline.goals(forDay: today)
        let todays = snaps.first { cal.isDate($0.date, inSameDayAs: today) }
        let status = Metrics.dayGoalStatus(todays, goals: goals)
        let wkGoals = timeline.goals(forWeekStarting: ws)
        let week = Metrics.weekStatus(snaps, weekStart: ws, goals: wkGoals, today: today)
        let stepsWeek = Metrics.stepsWeekStatus(snaps, weekStart: ws, goals: wkGoals, today: today)
        let workouts = Metrics.workoutWeek(snaps, weekStart: ws, goals: wkGoals, today: today)

        if goals == nil {
            Text("No goals set for this campaign yet.").foregroundStyle(theme.muted)
        } else {
            Text("Today").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
            goalRow("Protein", value: todays?.proteinG, goal: goals?.proteinDaily, unit: "g", met: status.protein)
            goalRow("Steps", value: todays?.steps, goal: goals?.dailyStepsGoal, unit: "", met: status.steps)
            goalRow("Water", value: todays?.waterMl, goal: goals?.waterDailyMl, unit: "ml", met: status.water)
            if !(goals?.hasDailyGoals ?? false) { Text("No daily goals set.").font(.caption).foregroundStyle(theme.muted) }

            if goals?.hasWeeklyGoals == true {
                Divider()
                Text("This week").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
                if week.goal != nil { weekRow(week) }
                if stepsWeek.goal != nil { stepsRow(stepsWeek) }
                if workouts.target != nil { workoutRow(workouts) }
            }
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

    private func stepsRow(_ w: WeekStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Steps, weekly average")
                Spacer()
                Text("avg \(Int((w.average ?? 0).rounded()).formatted()) / \(Int((w.dailyTarget ?? 0).rounded()).formatted())")
                    .font(.subheadline).monospacedDigit().foregroundStyle(theme.muted)
                StatusIcon(ok: w.outcome == .met ? true : w.outcome == .missed ? false : nil)
            }
            ProgressView(value: min((w.average ?? 0) / max(w.dailyTarget ?? 1, 1), 1))
                .tint(w.outcome == .met ? theme.good : theme.accent)
            Text("\(w.daysWithCalories) of 7 days logged").font(.caption).foregroundStyle(theme.muted)
        }
    }

    private func workoutRow(_ w: WorkoutWeek) -> some View {
        let target = w.target ?? 0
        let open = w.possible - w.done
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Workout days")
                Spacer()
                Text("\(w.done) / \(target)").font(.subheadline).monospacedDigit().foregroundStyle(theme.muted)
                StatusIcon(ok: w.outcome == .met ? true : w.outcome == .missed ? false : nil)
            }
            ProgressView(value: min(Double(w.done) / Double(max(target, 1)), 1))
                .tint(w.outcome == .met ? theme.good : (w.outcome == .missed ? theme.bad : theme.accent))
            Text(w.outcome == .met ? "Target reached"
                 : w.outcome == .missed ? "Out of reach this week"
                 : "\(max(target - w.done, 0)) more needed · \(open) day\(open == 1 ? "" : "s") left to log one")
                .font(.caption).foregroundStyle(theme.muted)
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
        return "\(diff.formatted()) kcal/day \(side) the \(Int(target.rounded()).formatted()) kcal/day goal · \(days)"
    }

    // MARK: Past campaign

    @ViewBuilder private var summaryBody: some View {
        let r = Insights.goalResults(snaps, timeline: timeline, campaign: campaign, today: today)
        if r.dayTotal == 0 && r.weekTotal == 0 {
            Text("No goals were set in this campaign.").foregroundStyle(theme.muted)
        } else {
            summaryLine("Daily goals met", r.dayTotal == 0 ? "—" : "\(r.dayMet) of \(r.dayTotal) days")
            summaryLine("Weekly goals met", r.weekTotal == 0 ? "—" : "\(r.weekMet) of \(r.weekTotal) finished weeks")
            if let last = r.atEnd {
                Divider()
                Text("Goals at the end").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
                if let c = last.caloriesWeekly { summaryLine("Calories per day (weekly average)", "\((Double(c) / 7).rounded().formatted()) kcal, \(last.caloriesAtOrUnder ? "at or under" : "at or over")") }
                if let p = last.proteinDaily { summaryLine("Protein per day", "\(p) g") }
                if let s = last.stepsDaily { summaryLine(last.stepsIsWeeklyAverage ? "Steps, weekly average" : "Steps per day", s.formatted()) }
                if let n = last.workoutDaysWeekly { summaryLine("Workout days per week", "\(n)") }
                if let w = last.waterDailyMl { summaryLine("Water per day", "\(w.formatted()) ml") }
            }
        }
    }

    private func summaryLine(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(theme.muted) }.font(.subheadline)
    }
}
