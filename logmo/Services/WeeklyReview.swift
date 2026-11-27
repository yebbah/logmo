import Foundation

// MARK: - The review

enum ReviewVerdict: Equatable {
    case onTrack, mostlyOnTrack, needsAttention, notEnoughData
    var title: String {
        switch self {
        case .onTrack: "On track"
        case .mostlyOnTrack: "Mostly on track"
        case .needsAttention: "Needs attention"
        case .notEnoughData: "Not enough logged yet"
        }
    }
}

/// One row of the review: this week's value, last week's, and what it means, marked good, worth a look (.warn) or just information.
struct ReviewMetric: Identifiable, Equatable {
    var id: String
    var title: String
    var value: String
    var previous: String?
    var mark: WhyItem.Kind
    var text: String
}

struct ReviewRating: Identifiable, Equatable {
    var id: String { rating.rawValue }
    var rating: Rating
    var average: Double
    var change: Double?
}

/// A week looked back on: how it compared with the week before, metric by metric, with a plain summary. Calculated from the logs each time.
struct WeeklyReview: Equatable {
    var weekStart: Date
    var weekEnd: Date                  // the last day shown: the week's end, or today while it is still going
    var isFullWeek: Bool
    var kind: CampaignKind
    var weekNumber: Int
    var totalWeeks: Int?
    var daysCovered: Int
    var daysLogged: Int
    var compliedDays: Int
    var verdict: ReviewVerdict
    var summary: String
    var metrics: [ReviewMetric]
    var ratings: [ReviewRating]
    var notes: [WhyItem]

    /// The calculated facts as plain lines: what Apple Intelligence may rewrite from, and nothing else.
    var facts: String {
        var l = ["campaign: \(kind.title), week \(weekNumber)" + (totalWeeks.map { " of \($0)" } ?? ""), "verdict: \(verdict.title)",
                 "days covered: \(daysCovered); days with any log: \(daysLogged); days complied: \(compliedDays)"]
        for m in metrics { l.append("\(m.title): \(m.value)" + (m.previous.map { " (\($0))" } ?? "") + " [\(m.mark == .good ? "good" : (m.mark == .warn ? "watch" : "info"))] \(m.text)") }
        for n in notes { l.append("note: \(n.text)") }
        return l.joined(separator: "\n")
    }
}

// MARK: - Rules

enum ReviewRules {
    private struct Window {
        var from: Date, to: Date
        var days: [Date]
    }

    /// The review is offered on a week's last day (Sunday, with weeks running Monday to Sunday).
    static func isLastDayOfWeek(_ date: Date, calendar cal: Calendar = .current) -> Bool {
        let d = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: 6, to: Metrics.weekStart(of: d, calendar: cal)) == d
    }

    /// Reviews the week starting `ws`: its days so far when it is still going, compared with the seven days before it.
    static func review(campaign c: CampaignInfo, snaps: [DaySnapshot], timeline: GoalTimeline, measurements: [MeasureEntry], trend: [TrendPoint],
                       maintenance: MaintenanceEstimate?, week ws: Date, today: Date, required: Set<Tracker>, includeCycle: Bool, includeSick: Bool,
                       useLb: Bool, calendar cal: Calendar = .current) -> WeeklyReview {
        let t = cal.startOfDay(for: today)
        let weekEnd = cal.date(byAdding: .day, value: 6, to: ws)!
        let to = min(weekEnd, CampaignRules.lastDay(c, calendar: cal) ?? weekEnd, t)
        let from = max(ws, c.start)
        let days = dates(from, to, cal)
        let pws = cal.date(byAdding: .day, value: -7, to: ws)!
        let prevDays = dates(pws, cal.date(byAdding: .day, value: -1, to: ws)!, cal)
        let map = Dictionary(snaps.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let cur = days.compactMap { map[$0] }, prev = prevDays.compactMap { map[$0] }
        let goals = timeline.goals(forDay: to, calendar: cal)
        let full = to == weekEnd
        func wt(_ kg: Double) -> String { useLb ? String(format: "%.2f lb", abs(kg) * 2.20462) : String(format: "%.2f kg", abs(kg)) }
        func wt1(_ kg: Double) -> String { useLb ? String(format: "%.1f lb", kg * 2.20462) : String(format: "%.1f kg", kg) }
        func avg(_ xs: [Int]) -> Double? { xs.isEmpty ? nil : Double(xs.reduce(0, +)) / Double(xs.count) }
        func n(_ v: Double?) -> String { v.map { Int($0.rounded()).formatted() } ?? "—" }

        var metrics: [ReviewMetric] = []

        // Weight trend, and how far it moved in the week against what the campaign aims for.
        let rows = Metrics.weeklyTrendRows(trend, from: pws, through: to, limit: 520, calendar: cal)
        let wRow = rows.first { $0.weekStart == ws }, pRow = rows.first { $0.weekStart == pws }
        if let r = wRow, let ch = r.changeKg, let pct = r.changePercent {
            let band = SuggestionRules.targetBand(c.kind)
            let inBand = pct >= band.lowerBound && pct <= band.upperBound
            let soFar = !full && days.count < 4
            var text: String
            switch c.kind {
            case .cut: text = inBand ? "Down \(wt(ch)) (\(String(format: "%+.2f", pct))% of body weight), inside the range a cut aims for." : (ch < 0 ? "Down \(wt(ch)), but \(pct > band.upperBound ? "slower" : "faster") than a cut aims for." : "Up \(wt(ch)), the wrong way for a cut.")
            case .bulk: text = inBand ? "Up \(wt(ch)) (\(String(format: "%+.2f", pct))% of body weight), a steady gain for a bulk." : (ch > 0 ? "Up \(wt(ch)), \(pct > band.upperBound ? "faster" : "slower") than a bulk aims for." : "Down \(wt(ch)), the wrong way for a bulk.")
            case .maintenance: text = inBand ? "Steady: \(ch >= 0 ? "up" : "down") \(wt(ch)), what maintenance is for." : "Drifting \(ch > 0 ? "up" : "down") by \(wt(ch))."
            }
            if let g = c.targetWeightKg, let now = trend.last(where: { cal.startOfDay(for: $0.date) <= to }) {
                let gap = now.trendKg - g
                if abs(gap) < 0.1 { text += " You're at your target weight." }
                else if (c.kind == .cut && gap > 0) || (c.kind == .bulk && gap < 0) { text += " Trend now \(wt1(now.trendKg)), \(wt1(abs(gap))) \(gap > 0 ? "above" : "below") your \(wt1(g)) target." }
            }
            metrics.append(ReviewMetric(id: "weight", title: "Weight trend", value: String(format: "%+.2f %@", useLb ? ch * 2.20462 : ch, useLb ? "lb" : "kg"),
                                        previous: pRow?.changeKg.map { String(format: "last week %+.2f", useLb ? $0 * 2.20462 : $0) },
                                        mark: soFar ? .info : (inBand ? .good : .warn), text: soFar ? "So far this week. " + text : text))
        } else {
            metrics.append(ReviewMetric(id: "weight", title: "Weight trend", value: "N/A", previous: nil, mark: .info,
                                        text: "There is no earlier trend to compare with this week, or the trend was restarted. Weigh-ins this week: \(cur.filter { $0.weightKg != nil }.count)."))
        }

        // Calories.
        let goalCal = goals?.caloriesWeekly.map { Int((Double($0) / 7).rounded()) }
        let calDays = cur.compactMap(\.calories), prevCal = prev.compactMap(\.calories)
        if let a = avg(calDays) {
            var mark: WhyItem.Kind = .info
            var text = "Logged on \(calDays.count) of \(days.count) days."
            if let g = goalCal, g > 0 {
                let r = a / Double(g)
                mark = calDays.count >= 3 ? ((0.92...1.08).contains(r) ? .good : .warn) : .info
                text = (r > 1.08 ? "Above" : (r < 0.92 ? "Below" : "Close to")) + " your goal of \(g.formatted()). " + text
            }
            if let m = maintenance { text += " Estimated maintenance is \(m.kcalPerDay.formatted())" + (goalCal.map { g in Int((abs(1 - Double(g) / Double(m.kcalPerDay)) * 100).rounded()) >= 2 ? ", so your goal is about \(Int((abs(1 - Double(g) / Double(m.kcalPerDay)) * 100).rounded()))% \(g < m.kcalPerDay ? "below" : "above") it." : ", about your goal." } ?? ".") }
            metrics.append(ReviewMetric(id: "calories", title: "Calories", value: "\(n(a)) a day", previous: avg(prevCal).map { "last week \(n($0))" }, mark: mark, text: text))
        } else {
            metrics.append(ReviewMetric(id: "calories", title: "Calories", value: "—", previous: avg(prevCal).map { "last week \(n($0))" }, mark: .info, text: "No calories were logged, so intake isn't judged."))
        }

        // Protein goal days.
        if days.count > 0 {
            var p = Insights.proteinDays(snaps, timeline: timeline, from: from, to: to, calendar: cal)
            if to == t, !full { p.missed -= Insights.proteinDays(snaps, timeline: timeline, from: t, to: t, calendar: cal).missed }
            let counted = p.hit + p.missed
            let pp = Insights.proteinDays(snaps, timeline: timeline, from: pws, to: cal.date(byAdding: .day, value: -1, to: ws)!, calendar: cal)
            let avgP = avg(cur.compactMap(\.proteinG))
            if counted > 0, let g = goals?.proteinDaily {
                metrics.append(ReviewMetric(id: "protein", title: "Protein", value: "\(p.hit) of \(counted) days",
                                            previous: pp.hit + pp.missed > 0 ? "last week \(pp.hit) of \(pp.hit + pp.missed)" : nil,
                                            mark: Double(p.hit) / Double(counted) >= 0.7 ? .good : .warn,
                                            text: "You reached \(g) g on \(p.hit) of the \(counted) days that had a goal." + (avgP.map { " Average \(n($0)) g." } ?? "")))
            }
        }

        // Steps and water.
        let stepGoal = goals?.stepsDaily
        let stepDays = cur.compactMap(\.steps), prevSteps = prev.compactMap(\.steps)
        if let a = avg(stepDays) {
            var text = "Logged on \(stepDays.count) of \(days.count) days."
            var mark: WhyItem.Kind = .info
            if let g = stepGoal {
                mark = stepDays.count >= 3 ? (a >= 0.9 * Double(g) ? .good : .warn) : .info
                text = (a >= Double(g) ? "Above" : "Below") + " your \(g.formatted()) goal" + (avg(prevSteps).map { p in abs(a - p) >= 100 ? " and \(a >= p ? "up" : "down") \(n(abs(a - p))) on last week." : "." } ?? ".")
            }
            metrics.append(ReviewMetric(id: "steps", title: "Steps", value: "\(n(a)) a day", previous: avg(prevSteps).map { "last week \(n($0))" }, mark: mark, text: text))
        }
        let waterDays = cur.compactMap(\.waterMl), prevWater = prev.compactMap(\.waterMl)
        if let a = avg(waterDays) {
            var text = "Logged on \(waterDays.count) of \(days.count) days."
            var mark: WhyItem.Kind = .info
            if let g = goals?.waterDailyMl {
                let reached = waterDays.filter { $0 >= g }.count
                mark = waterDays.count >= 3 ? (Double(reached) / Double(waterDays.count) >= 0.6 ? .good : .warn) : .info
                text = "Your \(g.formatted()) ml goal was reached on \(reached) of \(waterDays.count) logged days."
            }
            metrics.append(ReviewMetric(id: "water", title: "Water", value: "\(n(a)) ml", previous: avg(prevWater).map { "last week \(n($0)) ml" }, mark: mark, text: text))
        }

        // Training, from what logmo has: lifting days, the performance rating and the strength minutes Apple Health recorded.
        let lift = cur.filter { $0.ratings["performance"] != nil }.count, prevLift = prev.filter { $0.ratings["performance"] != nil }.count
        let perf = avg(cur.compactMap { $0.ratings["performance"] }), prevPerf = avg(prev.compactMap { $0.ratings["performance"] })
        let minutes = cur.compactMap(\.strengthMinutes).reduce(0, +), prevMinutes = prev.compactMap(\.strengthMinutes).reduce(0, +)
        var tText = ""
        var tMark: WhyItem.Kind = .info
        if let g = goals?.workoutDaysWeekly {
            let expected = Int((Double(g) * Double(days.count) / 7).rounded(.down))
            tMark = expected >= 1 ? (lift >= expected ? .good : .warn) : .info
            tText = "Your goal is \(g) a week" + (prev.isEmpty ? "." : ", and last week was \(prevLift).")
        }
        if let p = perf { tText += " Training performance averaged \(String(format: "%.1f", p))" + (prevPerf.map { abs(p - $0) >= 0.1 ? " (\(p >= $0 ? "up" : "down") \(String(format: "%.1f", abs(p - $0))))" : "" } ?? "") + "." }
        if minutes > 0 { tText += " Apple Health recorded \(minutes) minutes of strength work" + (prevMinutes > 0 ? ", \(minutes >= prevMinutes ? "\(minutes - prevMinutes) more" : "\(prevMinutes - minutes) fewer") than last week." : ".") }
        metrics.append(ReviewMetric(id: "training", title: "Training", value: "\(lift) lifting \(lift == 1 ? "day" : "days")", previous: prev.isEmpty ? nil : "last week \(prevLift)", mark: tMark,
                                    text: tText.trimmingCharacters(in: .whitespaces).isEmpty ? "No training days were rated this week." : tText.trimmingCharacters(in: .whitespaces)))

        // How you felt.
        func ratingAvg(_ ds: [DaySnapshot], _ r: Rating) -> Double? { avg(ds.compactMap { $0.ratings[r.rawValue] }) }
        var ratings: [ReviewRating] = []
        for r in Rating.allCases {
            if let a = ratingAvg(cur, r) { ratings.append(ReviewRating(rating: r, average: a, change: ratingAvg(prev, r).map { a - $0 })) }
        }
        let ratedDays = cur.filter { !$0.ratings.isEmpty }.count
        var felt: [String] = [], feltWarn = false
        for r in ratings {
            guard let d = r.change, abs(d) >= 0.3 else { continue }
            let worse = (r.rating.betterWhen == .higher && d < 0) || (r.rating.betterWhen == .lower && d > 0)
            if r.rating.betterWhen != .neutral { felt.append("\(r.rating.rawValue) \(d > 0 ? "rose" : "fell") \(String(format: "%.1f", abs(d)))"); if worse && abs(d) >= 0.4 { feltWarn = true } }
        }
        if !ratings.isEmpty {
            metrics.append(ReviewMetric(id: "felt", title: "How you felt", value: "see below", previous: nil,
                                        mark: ratedDays < 3 ? .info : (feltWarn ? .warn : .good),
                                        text: felt.isEmpty ? "Your check-ins held steady on last week." : felt.joined(separator: ", ").prefix(1).uppercased() + felt.joined(separator: ", ").dropFirst() + "."
                                            + (feltWarn ? " Worth watching sleep and recovery next week." : "")))
        }

        // Measurements.
        let mine = MeasureRules.entries(measurements, in: c, through: to, calendar: cal)
        let thisWeek = mine.filter { $0.day >= ws && $0.day <= to }
        if c.measureEveryDays > 0 || !mine.isEmpty {
            if let latest = thisWeek.last {
                let before = mine.filter { $0.day < latest.day }.last
                var parts: [String] = []
                if let b = before {
                    for s in MeasureSite.allCases { if let a = latest.values[s], let o = b.values[s], abs(a - o) >= 0.05 { parts.append("\(s.short.lowercased()) \(String(format: "%+.1f", a - o)) cm") } }
                }
                let navel = latest.values[.navel].map { String(format: "Waist at the navel %.1f cm", $0) } ?? "Measurements taken"
                metrics.append(ReviewMetric(id: "measurements", title: "Measurements", value: "taken " + latest.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                                            previous: before.map { "before: " + $0.day.formatted(.dateTime.day().month(.abbreviated)) }, mark: .info,
                                            text: navel + (parts.isEmpty ? (before == nil ? ": the first reading, your baseline." : ", nothing moved since the last ones.") : ", since the last ones: " + parts.joined(separator: ", ") + ".")))
            } else {
                let next = MeasureRules.nextDue(c, today: to, calendar: cal)
                metrics.append(ReviewMetric(id: "measurements", title: "Measurements", value: "not taken", previous: nil, mark: .info,
                                            text: "Not taken this week" + (next.map { "; the next are due \($0.formatted(.dateTime.day().month(.abbreviated)))." } ?? ".")))
            }
        }

        // Days complied.
        let strip = from <= to ? Metrics.complianceStrip(snaps, from: from, to: to, today: today, required: required, timeline: timeline, calendar: cal) : []
        let complied = strip.filter { $0 == .complied }.count

        // Worth knowing.
        var notes: [WhyItem] = []
        let logged = cur.filter { !$0.logged.isEmpty }.count
        if ratedDays < min(5, days.count), days.count >= 3 { notes.append(WhyItem(kind: .warn, text: "Check-ins were done on \(ratedDays) of \(days.count) days, so the recovery picture rests on fewer days than usual.")) }
        if cur.filter({ $0.weightKg != nil }).count < min(3, days.count) && days.count >= 3 { notes.append(WhyItem(kind: .warn, text: "Only \(cur.filter { $0.weightKg != nil }.count) weigh-ins this week, so the weight reading is less certain.")) }
        if includeCycle, case let p = cur.filter(\.onPeriod).count, p > 0 { notes.append(WhyItem(kind: .info, text: "\(p) period \(p == 1 ? "day" : "days") this week can hold water and blur the scale.")) }
        if includeSick, case let s = cur.filter(\.isSick).count, s > 0 { notes.append(WhyItem(kind: .warn, text: "You were sick on \(s) \(s == 1 ? "day" : "days"), which can explain a weaker week.")) }

        // Verdict.
        let core = metrics.filter { ["weight", "calories", "protein", "steps", "water", "training"].contains($0.id) && $0.mark != .info }
        let share = core.isEmpty ? 0 : Double(core.filter { $0.mark == .good }.count) / Double(core.count)
        let feltBad = metrics.first { $0.id == "felt" }?.mark == .warn
        // The weight is what the campaign is for: a week moving the wrong way is never plain "on track".
        let weightBad = metrics.first { $0.id == "weight" }?.mark == .warn
        let verdict: ReviewVerdict = logged < 3 || core.count < 2 ? .notEnoughData : (share >= 0.8 && !feltBad && !weightBad ? .onTrack : (share >= 0.5 ? .mostlyOnTrack : .needsAttention))

        let review = WeeklyReview(weekStart: ws, weekEnd: to, isFullWeek: full, kind: c.kind, weekNumber: CampaignRules.weekNumber(c, today: ws, calendar: cal), totalWeeks: c.plannedWeeks,
                                  daysCovered: days.count, daysLogged: logged, compliedDays: complied, verdict: verdict, summary: "", metrics: metrics, ratings: ratings, notes: notes)
        var r = review
        r.summary = summary(review, goalCalories: goalCal, wt: wt)
        return r
    }

    /// A short, plain paragraph written from the rows: progress first, then food, then what to watch.
    static func summary(_ r: WeeklyReview, goalCalories: Int?, wt: (Double) -> String) -> String {
        func m(_ id: String) -> ReviewMetric? { r.metrics.first { $0.id == id } }
        if r.verdict == .notEnoughData { return "There isn't enough logged in this week yet to say how it went. A few more days of weigh-ins, food and check-ins will fill this in." }
        var s: [String] = []
        let lead: String = r.verdict == .onTrack ? "A solid week." : (r.verdict == .mostlyOnTrack ? "A good week with a few things to watch." : "A harder week.")
        s.append(lead)
        if let w = m("weight"), w.value != "N/A" { s.append("Your weight trend moved \(w.value)" + (w.mark == .good ? ", in the range this campaign aims for" : (w.mark == .warn ? ", outside the range this campaign aims for" : "")) + ".") }
        if let c = m("calories"), c.mark == .good { s.append("You stayed close to your calorie goal.") }
        else if let c = m("calories"), c.mark == .warn { s.append("Your calories were off your goal.") }
        if let p = m("protein") { s.append(p.mark == .good ? "You hit your protein goal on most days." : "Protein fell short on several days.") }
        if let t = m("training"), t.mark == .good { s.append("You trained as planned.") } else if let t = m("training"), t.mark == .warn { s.append("You trained less than planned.") }
        if let me = m("measurements"), me.value.hasPrefix("taken"), let range = me.text.range(of: "Waist at the navel ") { s.append(String(me.text[range.lowerBound...].prefix(while: { $0 != ":" && $0 != "," })) + ".") }
        if let f = m("felt"), f.mark == .warn { s.append("How you felt moved the wrong way, so watch sleep and recovery next week.") }
        return s.joined(separator: " ")
    }

    private static func dates(_ a: Date, _ b: Date, _ cal: Calendar) -> [Date] {
        guard a <= b else { return [] }
        let n = (cal.dateComponents([.day], from: a, to: b).day ?? 0) + 1
        return (0..<n).map { cal.date(byAdding: .day, value: $0, to: a)! }
    }
}
