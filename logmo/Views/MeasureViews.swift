import SwiftUI
import SwiftData
import Charts

/// The campaign setting: how often to take body measurements.
struct MeasureCadencePicker: View {
    @Environment(\.theme) private var theme
    @Binding var everyDays: Int
    let start: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Take body measurements").font(.subheadline.weight(.semibold)).foregroundStyle(theme.muted)
            Picker("Take body measurements", selection: $everyDays) {
                ForEach(MeasureCadence.allCases) { Text($0.title).tag($0.rawValue) }
            }.pickerStyle(.segmented)
            Text(caption).font(.caption).foregroundStyle(theme.muted)
        }
        .padding(.vertical, 2)
    }

    private var caption: String {
        guard everyDays > 0 else { return "No measurements are asked for in this campaign. You can still add one any day." }
        let f = Date.FormatStyle().day().month(.abbreviated)
        let cal = Calendar.current
        let dates = (0..<3).map { cal.date(byAdding: .day, value: $0 * everyDays, to: cal.startOfDay(for: start))! }
        let every = everyDays == 7 ? "every week" : (everyDays == 14 ? "every two weeks" : "every four weeks")
        return "First on the start day (\(dates[0].formatted(f))), then \(every): \(dates[1].formatted(f)), \(dates[2].formatted(f)). Monthly means every four weeks."
    }
}

/// The Log screen's Measurements section: open on the days the campaign asks for them, otherwise collapsed so any day can add one.
struct MeasurementsSection: View {
    @Environment(\.theme) private var theme
    @Binding var texts: [MeasureSite: String]
    let due: Bool
    let last: MeasureEntry?
    @State private var open = false

    var body: some View {
        Section {
            if due || open || texts.values.contains(where: { !$0.isEmpty }) {
                ForEach(MeasureSite.allCases) { s in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title)
                            if let h = s.hint { Text(h).font(.caption2).foregroundStyle(theme.muted) }
                        }
                        Spacer()
                        if let v = last?.values[s] { Text("last \(String(format: "%.1f", v))").font(.caption2).foregroundStyle(theme.muted) }
                        TextField("cm", text: Binding(get: { texts[s] ?? "" }, set: { texts[s] = $0 }))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 64)
                    }
                }
                Text("In centimetres, relaxed, at about the same time of day. Fill in what you measured; blanks are fine. Typed here only; nothing comes from Apple Health.")
                    .font(.caption).foregroundStyle(theme.muted)
            } else {
                Button("Add measurements") { open = true }
            }
        } header: {
            HStack {
                Text("Measurements")
                if due { Text("Due today").font(.caption2.weight(.semibold)).foregroundStyle(theme.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(theme.accent.opacity(0.12), in: Capsule()).textCase(nil) }
            }
        }
        .listRowBackground(theme.card)
    }
}

/// A line per measured site over a campaign, with a legend that switches sites on and off, and the change since the first reading.
struct MeasurementsChartCard: View {
    @Environment(\.theme) private var theme
    let entries: [MeasureEntry]          // already limited to the campaign being shown
    let kind: CampaignKind?
    var title = "Body measurements"
    @State private var hidden: Set<MeasureSite> = []

    private let palette: [MeasureSite: Color] = [
        .navel: .blue, .belowNavel: .indigo, .aboveNavel: .teal, .chest: .orange, .thighs: .green, .calves: .pink, .biceps: .purple,
    ]

    var body: some View {
        let sites = MeasureSite.allCases.filter { !MeasureRules.series(entries, $0).isEmpty }
        let changes = MeasureRules.changes(entries)
        Card(title: title) {
            if sites.isEmpty {
                Text("No measurements in this campaign yet. Add them from the Log screen.").font(.subheadline).foregroundStyle(theme.muted)
            } else {
                let shown = sites.filter { !hidden.contains($0) }
                // Each site is drawn as its change from its own first reading, so waist (about 85 cm) and calves (about 37 cm) share one scale
                // and the lines show direction instead of sitting flat at different heights.
                Chart {
                    RuleMark(y: .value("No change", 0)).foregroundStyle(theme.muted.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1))
                    ForEach(shown) { s in
                        let ser = MeasureRules.series(entries, s)
                        let base = ser.first?.cm ?? 0
                        ForEach(Array(ser.enumerated()), id: \.offset) { _, p in
                            LineMark(x: .value("Day", p.day), y: .value("Change, cm", p.cm - base), series: .value("Site", s.short))
                                .foregroundStyle(palette[s] ?? .gray).interpolationMethod(.monotone)
                            PointMark(x: .value("Day", p.day), y: .value("Change, cm", p.cm - base)).foregroundStyle(palette[s] ?? .gray).symbolSize(28)
                        }
                    }
                }
                .chartYAxisLabel("cm change since the first reading", position: .top, alignment: .leading)
                .chartYScale(domain: .automatic(includesZero: true))
                .frame(height: 200)
                FlowLegend(sites: sites, hidden: $hidden, palette: palette)
                VStack(spacing: 0) {
                    HStack {
                        Text("Site").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Now").frame(width: 56, alignment: .trailing)
                        Text("Change").frame(width: 72, alignment: .trailing)
                    }.font(.caption2.weight(.semibold)).foregroundStyle(theme.muted).padding(.vertical, 6)
                    ForEach(sites) { s in
                        Divider()
                        HStack {
                            Text(s.title).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%.1f", MeasureRules.series(entries, s).last?.cm ?? 0)).font(.subheadline).monospacedDigit().frame(width: 56, alignment: .trailing)
                            Text(changes[s].map { abs($0) < 0.05 ? "0.0 cm" : String(format: "%+.1f cm", $0) } ?? "—").font(.subheadline.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(color(changes[s], s)).frame(width: 72, alignment: .trailing)
                        }.padding(.vertical, 6)
                    }
                }
                Text("Change is the latest reading minus the first in this campaign (needs two readings a week apart). Green fits the campaign: down on a cut, up on a bulk (not for the waist, which stays grey). Tap a site above to hide or show its line.")
                    .font(.caption).foregroundStyle(theme.muted)
            }
        }
    }

    private func color(_ change: Double?, _ s: MeasureSite) -> Color {
        guard let c = change, abs(c) >= 0.05, let kind else { return theme.muted }
        switch kind {
        case .cut: return c < 0 ? theme.good : theme.muted
        case .bulk: return (!s.isWaist && c > 0) ? theme.good : theme.muted
        case .maintenance: return theme.muted
        }
    }
}

/// Legend chips that wrap onto several lines and toggle a site.
private struct FlowLegend: View {
    @Environment(\.theme) private var theme
    let sites: [MeasureSite]
    @Binding var hidden: Set<MeasureSite>
    let palette: [MeasureSite: Color]

    var body: some View {
        FlexibleRow(spacing: 8) {
            ForEach(sites) { s in
                let off = hidden.contains(s)
                Button {
                    if off { hidden.remove(s) } else if hidden.count < sites.count - 1 { hidden.insert(s) }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(off ? Color.clear : (palette[s] ?? .gray)).overlay(Circle().stroke(palette[s] ?? .gray, lineWidth: 1.5)).frame(width: 9, height: 9)
                        Text(s.short).font(.caption).foregroundStyle(off ? theme.muted : Color.primary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(theme.track.opacity(0.6), in: Capsule())
                }.buttonStyle(.plain)
            }
        }
    }
}

/// A simple wrapping row layout.
private struct FlexibleRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
