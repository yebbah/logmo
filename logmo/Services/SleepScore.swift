import Foundation

/// Turns what Apple Health records about a night (duration, and when it is there, time awake and deep plus REM) into the
/// 1 to 5 sleep rating logmo uses. Health gives hours, not a score, so the scale is ours and is spelled out here.
/// It is an estimate of quality from the numbers, not a measurement of how rested someone feels, so the person can always
/// change it.
struct SleepResult: Equatable {
    var score: Int
    var headline: String           // "6 h 12 min asleep: 3 of 5"
    var detail: String             // why, in plain words
    var caveat: String?            // when the recording may not be the whole night
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

    /// A broken night or little deep and REM sleep can lower the score by one, never more, and never raise it.
    static let efficiencyFloor = 0.80          // asleep time ÷ (asleep + awake time during the night)
    static let restorativeFloor = 0.20         // deep + REM ÷ asleep time, judged only for nights of 6 h or more
    static let veryShortMinutes = 180

    static func score(asleepMinutes: Int, awakeMinutes: Int? = nil, deepRemMinutes: Int? = nil) -> SleepResult {
        let base = durationScore(asleepMinutes)
        var penalty = 0
        var notes: [String] = []
        if let awake = awakeMinutes, asleepMinutes + awake > 0 {
            let eff = Double(asleepMinutes) / Double(asleepMinutes + awake)
            if eff < efficiencyFloor {
                penalty = 1
                notes.append("You were awake for about \(awake) min during the night, so only \(Int((eff * 100).rounded()))% of it was sleep.")
            }
        }
        if let dr = deepRemMinutes, asleepMinutes >= 360 {
            let share = Double(dr) / Double(asleepMinutes)
            if share < restorativeFloor && penalty == 0 {
                penalty = 1
                notes.append("Deep and REM sleep made up \(Int((share * 100).rounded()))% of the night, which is low.")
            }
        }
        let score = max(base - penalty, 1)
        var detail: String
        switch base {
        case 5: detail = "That is within the 7½ to 9½ hours that suit most adults."
        case 4: detail = asleepMinutes > 570 ? "That is longer than the 7½ to 9½ hours that suit most adults." : "That is a little under the 7½ to 9½ hours that suit most adults."
        case 3: detail = "That is under the 7 to 9 hours adults usually need."
        case 2: detail = "That is well under the 7 to 9 hours adults usually need."
        default: detail = "That is far under the 7 to 9 hours adults usually need."
        }
        if !notes.isEmpty { detail += " " + notes.joined(separator: " ") }
        return SleepResult(score: score, headline: "\(hm(asleepMinutes)) asleep: \(score) of 5", detail: detail,
                           caveat: asleepMinutes < veryShortMinutes
                               ? "This is very short, so it may be an incomplete recording or just a nap. Change the rating if that is the case." : nil)
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
}
