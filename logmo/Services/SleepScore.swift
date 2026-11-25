import Foundation

/// Turns what Apple Health records about a night into the 1 to 5 sleep rating logmo uses. Health gives hours and, from a
/// watch, sleep stages, but no score, so the scale is ours and is spelled out here. It is an estimate of quality from the
/// numbers, not a measurement of how rested someone feels, so the person can always change it.
struct SleepResult: Equatable {
    var score: Int
    var headline: String           // "6 h 12 min asleep: 3 of 5"
    var detail: String             // why, in plain words, including the stages when there are any
    var caveat: String?            // when the recording may not be the whole night
    var stageAdjustment: Int       // what the stages and wake-ups added or took off (0 without stage data)
}

enum SleepScore {
    /// Duration is the base. Adults usually need 7 to 9 hours, so that range, and a little either side, is where the top scores are.
    ///   5: 7 h 30 min to 9 h 30 min    4: 6 h 45 min to 7 h 29 min (or longer than 9 h 30 min)
    ///   3: 6 h to 6 h 44 min           2: 4 h 30 min to 5 h 59 min     1: under 4 h 30 min
    static func durationScore(_ minutes: Int) -> Int {
        switch minutes {
        case 450...570: 5
        case 405..<450: 4
        case 571...: 4
        case 360..<405: 3
        case 270..<360: 2
        default: 1
        }
    }

    /// Stage quality (0 to 1) when the watch recorded stages: how unbroken the night was, and how much of it was deep and REM.
    /// Each part is scaled between a low and a high mark taken from typical adult nights.
    ///   unbroken: asleep ÷ (asleep + awake)   0.70 → 0,  0.90 → 1      (weight 40%)
    ///   deep:     share of the night          5% → 0,    13% → 1       (weight 30%; typical 13 to 23%)
    ///   REM:      share of the night          10% → 0,   20% → 1       (weight 30%; typical 20 to 25%)
    /// Without time-awake data the other two share the weight equally.
    static func stageQuality(asleep: Int, awake: Int?, deep: Int, rem: Int) -> Double {
        func scale(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max((x - lo) / (hi - lo), 0), 1) }
        let d = scale(Double(deep) / Double(asleep), 0.05, 0.13), r = scale(Double(rem) / Double(asleep), 0.10, 0.20)
        guard let awake, asleep + awake > 0 else { return 0.5 * d + 0.5 * r }
        return 0.4 * scale(Double(asleep) / Double(asleep + awake), 0.70, 0.90) + 0.3 * d + 0.3 * r
    }

    /// What the stages add to or take off the duration score: strong stages +1 (only for nights of 6 h or more, and never
    /// above 5), typical 0, weak -1, very weak -2. The score never goes below 1.
    static func stageAdjustment(quality: Double, asleep: Int) -> Int {
        if quality >= 0.85 { return asleep >= 360 ? 1 : 0 }
        if quality >= 0.55 { return 0 }
        return quality >= 0.30 ? -1 : -2
    }

    static let veryShortMinutes = 180
    static let brokenNightBelow = 0.80          // asleep ÷ (asleep + awake)

    static func score(asleepMinutes: Int, awakeMinutes: Int? = nil, deepMinutes: Int? = nil, remMinutes: Int? = nil) -> SleepResult {
        let base = durationScore(asleepMinutes)
        var adjustment = 0
        var stageText = ""
        if let deep = deepMinutes, let rem = remMinutes, asleepMinutes > 0 {
            let q = stageQuality(asleep: asleepMinutes, awake: awakeMinutes, deep: deep, rem: rem)
            adjustment = stageAdjustment(quality: q, asleep: asleepMinutes)
            if let a = awakeMinutes, asleepMinutes + a > 0, Double(asleepMinutes) / Double(asleepMinutes + a) < brokenNightBelow {
                adjustment = min(adjustment, -1)                     // a night broken up by waking always loses a point, however the stages look
            }
            var parts: [String] = []
            if let a = awakeMinutes, asleepMinutes + a > 0 {
                parts.append("awake \(hm(a)) (\(Int((Double(asleepMinutes) / Double(asleepMinutes + a) * 100).rounded()))% of the night asleep)")
            }
            parts.append("deep \(hm(deep)) (\(pct(deep, asleepMinutes)))")
            parts.append("REM \(hm(rem)) (\(pct(rem, asleepMinutes)))")
            stageText = " Your watch recorded " + parts.joined(separator: ", ") + ". "
            switch adjustment {
            case 1: stageText += base == 5 ? "Few wake-ups and good deep and REM sleep keep it at the top." : "Few wake-ups and good deep and REM sleep raise the score by one."
            case 0: stageText += "The stages and wake-ups look typical, so the score stays."
            case -1: stageText += "Wake-ups or low deep and REM sleep lower the score by one."
            default: stageText += "Many wake-ups or very little deep and REM sleep lower the score by two."
            }
        }
        let score = min(max(base + adjustment, 1), 5)
        let applied = score - base
        var detail: String
        switch base {
        case 5: detail = "That is within the 7½ to 9½ hours that suit most adults."
        case 4: detail = asleepMinutes > 570 ? "That is longer than the 7½ to 9½ hours that suit most adults." : "That is a little under the 7½ to 9½ hours that suit most adults."
        case 3: detail = "That is under the 7 to 9 hours adults usually need."
        case 2: detail = "That is well under the 7 to 9 hours adults usually need."
        default: detail = "That is far under the 7 to 9 hours adults usually need."
        }
        return SleepResult(score: score, headline: "\(hm(asleepMinutes)) asleep: \(score) of 5", detail: detail + stageText,
                           caveat: asleepMinutes < veryShortMinutes
                               ? "This is very short, so it may be an incomplete recording or just a nap. Change the rating if that is the case." : nil,
                           stageAdjustment: applied)
    }

    /// A night is scored once the morning is over. Earlier, Health may still be adding to it, so only the hours are shown.
    static func isFinished(day: Date, now: Date, calendar cal: Calendar = .current) -> Bool {
        let today = cal.startOfDay(for: now)
        if cal.startOfDay(for: day) < today { return true }
        return cal.component(.hour, from: now) >= 11
    }

    static func hm(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
    private static func pct(_ part: Int, _ whole: Int) -> String { "\(Int((Double(part) / Double(max(whole, 1)) * 100).rounded()))%" }
}
