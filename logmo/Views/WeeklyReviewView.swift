import SwiftUI
import SwiftData

/// The weekly review: how this week (so far, or last week) went against the campaign and against the week before.
/// Worked out from the logs each time; nothing is stored and no goal changes. "Plan next week" hands over to the suggestion.
struct WeeklyReviewSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @AppStorage(SettingsKey.required) private var requiredRaw = RequiredTrackers.defaultRaw
    @AppStorage(SettingsKey.trackCycle) private var trackCycle = false
    @AppStorage(SettingsKey.trackSick) private var trackSick = false
    @Query(sort: \DayLog.day) private var logs: [DayLog]
    @Query private var weekGoals: [WeekGoal]
    @Query(sort: \Campaign.number) private var campaigns: [Campaign]

    let campaign: CampaignInfo
    /// "Plan next week": called before this sheet closes; the caller opens the suggestion once the sheet has finished dismissing.
    var onPlan: (() -> Void)? = nil

    enum Which: String { case thisWeek, lastWeek }
    @State private var which: Which = .thisWeek
    @State private var polished: [Which: String] = [:]
    @State private var polishing = false

    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var thisWeek: Date { Metrics.weekStart(of: today) }
    private var lastWeek: Date { cal.date(byAdding: .day, value: -7, to: thisWeek)! }
    private var hasLastWeek: Bool { cal.date(byAdding: .day, value: 6, to: lastWeek)! >= campaign.start }
    private var weekStart: Date { which == .thisWeek ? thisWeek : lastWeek }
    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }
    private var canPlan: Bool { onPlan != nil && PlanRules.bounds(campaign, today: today).editable != nil }

    private var review: WeeklyReview {
        let infos = campaigns.map(\.info)
        let snaps = logs.map(\.snapshot)
        let seeds = CampaignRules.trendSeeds(infos)
        let end = min(cal.date(byAdding: .day, value: 6, to: weekStart)!, today)
        return ReviewRules.review(campaign: campaign, snaps: snaps, timeline: GoalTimeline(weekGoals, campaigns: infos),
                                  measurements: logs.compactMap { l in l.measures.isEmpty ? nil : MeasureEntry(day: l.day, values: l.measures.values) },
                                  trend: Metrics.weightTrend(snaps, through: today, smoothingDays: smoothing, seeds: seeds),
                                  maintenance: Maintenance.estimate(snaps, through: end, smoothingDays: smoothing, seeds: seeds, profile: MaintenanceProfile.load()),
                                  week: weekStart, today: today, required: RequiredTrackers.parse(requiredRaw),
                                  includeCycle: trackCycle, includeSick: trackSick, useLb: unit == .lb)
    }

    var body: some View {
        NavigationStack {
            let r = review
            ScrollView {
                VStack(spacing: 16) {
                    header(r)
                    if hasLastWeek {
                        Picker("Week", selection: $which) {
                            Text("This week").tag(Which.thisWeek)
                            Text("Last week").tag(Which.lastWeek)
                        }.pickerStyle(.segmented)
                    }
                    summaryCard(r)
                    if r.verdict != .notEnoughData {
                        metricsCard(r)
                        if !r.ratings.isEmpty { ratingsCard(r) }
                        if !r.notes.isEmpty { notesCard(r) }
                    }
                    nextCard
                }
                .padding()
            }
            .background(theme.bg)
            .navigationTitle(which == .thisWeek ? "Week \(r.weekNumber) review" : "Last week's review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: which) { await polish(review) }
        }
        .presentationDetents([.large])
    }

    // MARK: pieces

    private func header(_ r: WeeklyReview) -> some View {
        let f = Date.FormatStyle().day().month(.abbreviated)
        let pws = cal.date(byAdding: .day, value: -7, to: r.weekStart)!
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(r.weekStart.formatted(f)) – \(r.weekEnd.formatted(f)) · \(r.kind.title), week \(r.weekNumber)" + (r.totalWeeks.map { " of \($0)" } ?? ""))
                .font(.subheadline).foregroundStyle(theme.muted)
            Text("Compared with \(pws.formatted(f)) – \(cal.date(byAdding: .day, value: 6, to: pws)!.formatted(f))" + (r.isFullWeek ? "" : ". This week so far: \(r.daysCovered) \(r.daysCovered == 1 ? "day" : "days")."))
                .font(.caption).foregroundStyle(theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryCard(_ r: WeeklyReview) -> some View {
        let text = polished[which] ?? r.summary
        let color: Color = r.verdict == .onTrack || r.verdict == .mostlyOnTrack ? theme.good : (r.verdict == .needsAttention ? theme.warn : theme.muted)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(r.verdict.title).font(.caption.weight(.semibold)).foregroundStyle(color)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(color.opacity(0.12), in: Capsule())
                Spacer()
                if r.daysCovered > 0 { Text("\(r.compliedDays) of \(r.daysCovered) days complied").font(.caption).foregroundStyle(theme.muted) }
            }
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(theme.accent)
                Text(polished[which] != nil ? "Reworded by Apple Intelligence on your iPhone, using only these numbers."
                     : (polishing ? "Apple Intelligence is rewording this…" : "Written by logmo from your logs."))
                    .font(.caption).foregroundStyle(theme.muted)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metricsCard(_ r: WeeklyReview) -> some View {
        Card(title: "How the week went") {
            ForEach(r.metrics) { m in
                Divider()
                HStack(alignment: .top, spacing: 10) {
                    markIcon(m.mark)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(m.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(m.value).font(.subheadline.weight(.bold))
                        }
                        if let p = m.previous { Text(p).font(.caption2).foregroundStyle(theme.muted).frame(maxWidth: .infinity, alignment: .trailing) }
                        Text(m.text).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func ratingsCard(_ r: WeeklyReview) -> some View {
        Card(title: "Biofeedback") {
            Text("Average this week and the change on last week").font(.caption).foregroundStyle(theme.muted)
            ForEach(r.ratings) { x in
                Divider()
                HStack {
                    Text(x.rating.title).font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1f", x.average)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    Text(changeText(x)).font(.caption).monospacedDigit().foregroundStyle(changeColor(x)).frame(width: 66, alignment: .trailing)
                }
            }
            Text("Green moves the better way, amber the other way. Days without a rating aren't counted as zero.").font(.caption).foregroundStyle(theme.muted)
        }
    }

    private func notesCard(_ r: WeeklyReview) -> some View {
        Card(title: "Worth knowing") {
            ForEach(Array(r.notes.enumerated()), id: \.offset) { _, n in
                HStack(alignment: .top, spacing: 10) {
                    markIcon(n.kind)
                    Text(n.text).font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var nextCard: some View {
        Card(title: "Next") {
            if canPlan {
                Text("Plan next week with a conservative or an aggressive option, using what you logged.").font(.footnote).foregroundStyle(theme.muted)
                Button { onPlan?(); dismiss() } label: { Text("Plan next week").fontWeight(.semibold).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
            }
            Button("Done") { dismiss() }.frame(maxWidth: .infinity)
            Text("This review is worked out from your logs each time. It doesn't change your goals.").font(.caption).foregroundStyle(theme.muted)
        }
    }

    private func markIcon(_ k: WhyItem.Kind) -> some View {
        let color: Color = k == .good ? theme.good : (k == .warn ? theme.warn : theme.accent)
        return Image(systemName: k == .good ? "checkmark" : (k == .warn ? "exclamationmark" : "info"))
            .font(.caption.weight(.bold)).frame(width: 24, height: 24).foregroundStyle(color).background(color.opacity(0.14), in: Circle())
    }

    private func changeText(_ x: ReviewRating) -> String {
        guard let c = x.change else { return "–" }
        return abs(c) < 0.05 ? "– 0.0" : String(format: "%@ %.1f", c > 0 ? "▲" : "▼", abs(c))
    }

    private func changeColor(_ x: ReviewRating) -> Color {
        guard let c = x.change, abs(c) >= 0.05 else { return theme.muted }
        switch x.rating.betterWhen {
        case .higher: return c > 0 ? theme.good : theme.warn
        case .lower: return c < 0 ? theme.good : theme.warn
        case .neutral: return theme.muted
        }
    }

    /// Asks Apple Intelligence to reword the summary, giving up after 20 seconds and keeping the calculated one.
    private func polish(_ r: WeeklyReview) async {
        guard polished[which] == nil, r.verdict != .notEnoughData, AIAdvisor.availability == .available else { return }
        polishing = true
        let key = which
        let answer = await SuggestSheet.withTimeout(seconds: 20) { await AIAdvisor.polishReview(r) }
        polishing = false
        if let text = answer.value { polished[key] = text }
    }
}
