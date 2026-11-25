import SwiftUI
import SwiftData

private let shortDate = Date.FormatStyle().day().month(.abbreviated)

// MARK: - Prompt

/// Asks about the weekly plan when something needs a decision. See PlanRules.prompt.
struct PlanPromptBanner: View {
    @Environment(\.theme) private var theme
    let prompt: PlanPrompt
    let onKeep: () -> Void
    let onChange: () -> Void
    var onSuggest: (() -> Void)? = nil

    var body: some View {
        switch prompt {
        case .none:
            EmptyView()
        case .setGoals:
            box(tint: theme.accent, icon: "target", title: "Set your weekly goals",
                text: "Calories, protein, steps, water and workouts, for this campaign.", keep: nil, change: "Set goals")
        case .carriedOver:
            box(tint: theme.warn, icon: "exclamationmark.circle", title: "This week's goals are carried over",
                text: "They're last week's. Keep them, or change them for this week.", keep: "Keep them", change: "Change them")
        case .planNext(let week):
            box(tint: theme.accent, icon: "target", title: "Plan next week",
                text: "It's Sunday. \(week.formatted(shortDate)) isn't set yet.", keep: "Same as this week", change: "Change it")
        }
    }

    private func box(tint: Color, icon: String, title: String, text: String, keep: String?, change: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).foregroundStyle(tint).font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(text).font(.subheadline).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                if let keep { pill(keep, filled: false, action: onKeep) }
                pill(change, filled: true, action: onChange)
            }
            if let onSuggest {
                Button(action: onSuggest) {
                    Label("Suggest next week", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 24).padding(.vertical, 12)
                        .foregroundStyle(theme.accent).background(theme.card, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 24).padding(.vertical, 12).padding(.horizontal, 8)
                .foregroundStyle(filled ? theme.onAccent : theme.accent)
                .background(filled ? theme.accent : theme.card, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
}

// MARK: - A week's goals in one line

/// "2,100 kcal/day · 150 g protein · …", with what changed from the week before highlighted and its old value beside it.
struct GoalsLine: View {
    @Environment(\.theme) private var theme
    let goals: GoalSet?
    let previous: GoalSet?

    private func pieces(_ g: GoalSet?) -> [String] {
        guard let g else { return [] }
        var out: [String] = []
        if let c = g.caloriesWeekly { out.append("\(Int((Double(c) / 7).rounded()).formatted()) kcal/day") }
        if let p = g.proteinDaily { out.append("\(p) g protein") }
        if let s = g.stepsDaily { out.append("\(s.formatted()) steps\(g.stepsIsWeeklyAverage ? " avg" : "")") }
        if let w = g.waterDailyMl { out.append("\(w.formatted()) ml") }
        if let n = g.workoutDaysWeekly { out.append("\(n) workouts") }
        if let c = g.carbsDaily { out.append("\(c) g carbs") }
        if let f = g.fatDaily { out.append("\(f) g fat") }
        return out
    }

    /// One text per goal, highlighted when it differs from the week before.
    private func parts() -> [Text] {
        let cur = pieces(goals), prev = pieces(previous)
        return cur.map { piece in
            // match by the unit word, so "1,800 kcal/day" is compared with last week's "kcal/day"
            let key = piece.split(separator: " ").dropFirst().joined(separator: " ")
            let old = prev.first { $0.split(separator: " ").dropFirst().joined(separator: " ") == key }
            if previous != nil, old != piece {
                let was = old.map { " (was \($0.split(separator: " ").first.map(String.init) ?? ""))" } ?? " (new)"
                return Text(piece).bold().foregroundStyle(theme.accent) + Text(was).font(.caption2).foregroundStyle(theme.muted)
            }
            return Text(piece).foregroundStyle(theme.muted)
        }
    }

    var body: some View {
        if goals == nil {
            Text("No goals set").font(.footnote).foregroundStyle(theme.muted)
        } else {
            parts().enumerated().reduce(Text("")) { acc, item in
                item.offset == 0 ? item.element : acc + Text(" · ").foregroundStyle(theme.muted) + item.element
            }
            .font(.footnote)
        }
    }
}

// MARK: - One week

struct WeekRowCard: View {
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    let row: WeekPlanRow
    var plain = false                  // no card of its own, for use inside another card
    var onEdit: (() -> Void)? = nil
    var onKeep: (() -> Void)? = nil

    private var range: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: row.weekStart)!
        return "\(row.weekStart.formatted(shortDate)) – \(end.formatted(shortDate))"
    }
    /// The weight trend at the end of the week and how it moved from the week before, kept as that week's history.
    private func trendLine(_ kg: Double) -> some View {
        let unit = WeightUnit(rawValue: unitRaw) ?? .kg
        var text = String(format: "Weight trend %.2f %@", unit.fromKg(kg), unit.rawValue)
        if let c = row.trendChangeKg {
            let d = unit.fromKg(kg) - unit.fromKg(kg - c)
            text += String(format: " · %+.2f %@", d, unit.rawValue) + (row.trendChangePercent.map { String(format: " (%+.2f%%)", $0) } ?? "") + " from the week before"
        } else {
            text += " · change N/A"
        }
        if row.phase == .current { text += " (so far)" }
        return Label(text, systemImage: "scalemass").font(.caption).foregroundStyle(theme.muted).labelStyle(.titleAndIcon)
    }

    private var tag: String? {
        switch row.phase {
        case .current: return "this week"
        case .future: return Calendar.current.isDate(row.weekStart, inSameDayAs: Calendar.current.date(byAdding: .day, value: 7, to: Metrics.weekStart(of: Date()))!) ? "next week" : nil
        case .past: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(range).font(.headline)
                if let tag { Text(tag).font(.caption).foregroundStyle(row.phase == .current ? theme.accent : theme.muted) }
                Spacer()
                if row.goals != nil { chip }
                if row.phase == .past, row.goals?.hasWeeklyGoals == true {
                    StatusIcon(ok: row.outcome == .met ? true : (row.outcome == .missed ? false : nil))
                }
            }
            GoalsLine(goals: row.goals, previous: row.previous)

            if row.phase != .future, row.days > 0 {
                HStack(spacing: 8) {
                    Text("\(row.compliedDays) of \(row.days) days complied").font(.caption).foregroundStyle(theme.muted)
                    Spacer()
                    if row.phase == .past, row.outcome == .missed, let reason = row.reason {
                        Text(reason).font(.caption).foregroundStyle(theme.bad).multilineTextAlignment(.trailing)
                    }
                }
                strip
            }
            if let t = row.trendKg { trendLine(t) }
            if row.phase == .past {
                Label("Locked", systemImage: "lock.fill").font(.caption2).foregroundStyle(theme.muted)
            }
            if onEdit != nil || onKeep != nil {
                HStack(spacing: 14) {
                    if let onKeep, !row.isSet, row.goals != nil {
                        Button(row.phase == .current ? "Keep" : "Same as before", action: onKeep).font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    if let onEdit { Button("Edit", action: onEdit).font(.subheadline.weight(.semibold)) }
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }
        }
        .padding(plain ? 0 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(plain ? Color.clear : theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(plain ? Color.clear : (row.phase == .current ? theme.accent.opacity(0.4) : theme.border),
                                                           lineWidth: row.phase == .current ? 1.5 : 1))
    }

    private var chip: some View {
        Text(row.isSet ? "Set by you" : "Carried over").font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(row.isSet ? theme.good : theme.warn)
            .background((row.isSet ? theme.good : theme.warn).opacity(0.14), in: Capsule())
    }

    private var strip: some View {
        HStack(spacing: 2) {
            ForEach(Array(row.strip.enumerated()), id: \.offset) { _, d in
                RoundedRectangle(cornerRadius: 2)
                    .fill(d == .complied ? theme.good : (d == .missed ? theme.bad : theme.track))
                    .frame(height: 8)
            }
            // unfilled days still to come keep the strip seven wide
            ForEach(0..<max(7 - row.strip.count, 0), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2).fill(theme.track.opacity(0.5)).frame(height: 8)
            }
        }
    }
}

// MARK: - The plan of one campaign

struct WeeklyPlanView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.required) private var requiredRaw = RequiredTrackers.defaultRaw
    @Query(sort: \Campaign.number) private var campaigns: [Campaign]
    @Query(sort: \DayLog.day) private var logs: [DayLog]
    @Query private var weekGoals: [WeekGoal]
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16

    let campaign: CampaignInfo
    @State private var editing: EditTarget?
    @State private var suggesting = false
    @State private var pendingEdit: EditTarget?        // "Edit first": opened once the suggestion sheet has dismissed

    struct EditTarget: Identifiable { var week: Date; var prefill: GoalSet? = nil; var id: Date { week } }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        let infos = campaigns.map(\.info)
        let snaps = logs.map(\.snapshot)
        let mine = weekGoals.filter { $0.campaignID == campaign.id }
        let byWeek = Dictionary(mine.map { ($0.weekStart, $0.goalSet) }, uniquingKeysWith: { a, _ in a })
        let explicit = PlanStore.explicitWeeks(weekGoals, campaignID: campaign.id)
        let rows = Insights.weeklyPlan(campaign, snaps: snaps, weeks: byWeek, explicit: explicit,
                                       timeline: GoalTimeline(weekGoals, campaigns: infos),
                                       required: RequiredTrackers.parse(requiredRaw), today: today,
                                       trend: Metrics.weightTrend(snaps, through: today, smoothingDays: smoothing, seeds: CampaignRules.trendSeeds(infos)))
        let prompt = PlanRules.prompt(campaign, hasAnyGoals: !mine.isEmpty, explicit: explicit, today: today)
        let editable = PlanRules.bounds(campaign, today: today).editable != nil

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(CampaignRules.titleWithPeriod(campaign, today: today))
                    .font(.footnote).foregroundStyle(theme.muted).padding(.horizontal, 2)
                Text("Each campaign keeps its own weekly goals.").font(.caption).foregroundStyle(theme.muted).padding(.horizontal, 2)

                PlanPromptBanner(prompt: prompt, onKeep: { keep(prompt) }, onChange: { change(prompt) },
                                 onSuggest: editable ? { suggesting = true } : nil)

                let future = rows.filter { $0.phase == .future }
                let current = rows.filter { $0.phase == .current }
                let past = rows.filter { $0.phase == .past }.reversed()

                if !current.isEmpty {
                    sectionTitle("This week")
                    ForEach(current) { r in
                        WeekRowCard(row: r, onEdit: editable ? { editing = EditTarget(week: r.weekStart) } : nil,
                                    onKeep: editable ? { PlanStore.confirm(context, campaignID: campaign.id, week: r.weekStart) } : nil)
                    }
                }
                if !future.isEmpty {
                    sectionTitle("Plan ahead")
                    ForEach(future) { r in
                        WeekRowCard(row: r, onEdit: editable ? { editing = EditTarget(week: r.weekStart) } : nil,
                                    onKeep: editable ? { PlanStore.confirm(context, campaignID: campaign.id, week: r.weekStart) } : nil)
                    }
                }
                if !past.isEmpty {
                    sectionTitle("Past weeks")
                    ForEach(Array(past)) { r in WeekRowCard(row: r) }
                    Text("Past weeks are locked, because changing one would change its result and your streaks. \"n of 7 days\" is how many days complied under that week's goals.")
                        .font(.caption2).foregroundStyle(theme.muted).padding(.horizontal, 2)
                }
            }
            .padding()
        }
        .background(theme.bg)
        .navigationTitle("Weekly plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            #if DEBUG
            // Debug aid for screenshots: -suggestOnAppear 1 opens the suggestion as the toolbar button would
            if UserDefaults.standard.bool(forKey: "suggestOnAppear") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { suggesting = true } }
            #endif
        }
        .sheet(item: $editing) { t in GoalsSheet(campaign: campaign, week: t.week, prefill: t.prefill) }
        .sheet(isPresented: $suggesting, onDismiss: {
            if let p = pendingEdit { pendingEdit = nil; editing = p }
        }) {
            SuggestSheet(campaign: campaign) { goals, week in pendingEdit = EditTarget(week: week, prefill: goals) }
        }
        .toolbar {
            if editable {
                ToolbarItem(placement: .primaryAction) {
                    Button { suggesting = true } label: { Label("Suggest next week", systemImage: "sparkles") }
                }
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(theme.muted).padding(.top, 6).padding(.horizontal, 2)
    }

    private func keep(_ p: PlanPrompt) {
        switch p {
        case .carriedOver(let w), .planNext(let w): PlanStore.confirm(context, campaignID: campaign.id, week: w)
        default: break
        }
    }
    private func change(_ p: PlanPrompt) {
        switch p {
        case .carriedOver(let w), .planNext(let w): editing = EditTarget(week: w)
        case .setGoals: editing = EditTarget(week: Metrics.weekStart(of: today))
        case .none: break
        }
    }
}

/// A read-only plan inside a campaign's look back: every week that has begun, newest first.
struct WeeklyPlanCard: View {
    @Environment(\.theme) private var theme
    let rows: [WeekPlanRow]
    let report: CampaignReport
    @State private var showAll = false

    var body: some View {
        let begun = rows.filter { $0.phase != .future }.reversed()
        let shown = showAll ? Array(begun) : Array(begun.prefix(4))
        Card(title: "Weekly plan", trailing: { Text("read-only").font(.caption).foregroundStyle(theme.muted) }) {
            if begun.isEmpty {
                Text("No weeks yet.").foregroundStyle(theme.muted)
            } else {
                Text(report.weeklyGoals > 0 ? "Weekly goals met in \(report.weeklyGoalsMet) of \(report.weeklyGoals) finished weeks." :
                        "The goals set for each week of this campaign, and how each week went.")
                    .font(.caption).foregroundStyle(theme.muted)
                ForEach(shown) { r in
                    Divider()
                    WeekRowCard(row: r, plain: true)
                }
                if begun.count > 4 {
                    Divider()
                    Button(showAll ? "Show fewer" : "Show all \(begun.count) weeks") { withAnimation { showAll.toggle() } }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}
