import Foundation

/// Estimated maintenance calories (TDEE): what you would eat to hold your weight. Worked out the way the S3 workbook does it:
/// smooth the weight, smooth the calories eaten, turn the weekly change in trend weight into a daily energy gap
/// (about 1,100 kcal a day for each kg gained or lost in a week), and subtract that gap from what was eaten. A loss
/// means you were eating below maintenance, so the estimate sits above your intake; a gain puts it below.
/// While there aren't enough weigh-ins or calorie logs the estimate is held where it was ("holding"), and it
/// starts only after ten days of history. A formula estimate from height, age, sex and activity is a starting point and a cross-check.

enum MaintenanceStatus: Equatable { case waiting, updating }
enum MaintenanceSource: Equatable { case trend, formula }

struct MaintenancePoint: Equatable, Identifiable {
    var date: Date
    var tdee: Double?                 // the smoothed estimate, carried forward through gaps; nil before the first one
    var intake: Double?               // smoothed calories eaten
    var status: MaintenanceStatus     // updating: recent weigh-ins and calorie logs are enough to move the estimate
    var id: Date { date }
}

struct MaintenanceEstimate: Equatable {
    var kcalPerDay: Int
    var source: MaintenanceSource
    var status: MaintenanceStatus     // a formula estimate is always "waiting": it doesn't move with your data
    var confidence: DataConfidence
    var series: [MaintenancePoint]    // empty for a formula estimate
    var formulaKcal: Int?             // from the profile, when one is set (also shown beside a trend estimate)
    var intakeKcal: Int?              // smoothed calories eaten now
}

/// Optional details for the formula estimate. Stored only on the phone.
struct MaintenanceProfile: Equatable {
    enum Sex: String, CaseIterable, Identifiable {
        case male, female, other
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }
    enum Activity: String, CaseIterable, Identifiable {
        case sedentary, light, moderate, very, extra
        var id: String { rawValue }
        var factor: Double { [.sedentary: 1.2, .light: 1.375, .moderate: 1.55, .very: 1.725, .extra: 1.9][self]! }
        var title: String {
            switch self {
            case .sedentary: "Sedentary: desk job, little exercise"
            case .light: "Light: exercise 1 to 3 days a week"
            case .moderate: "Moderate: exercise 3 to 5 days a week"
            case .very: "Very active: hard exercise 6 to 7 days a week"
            case .extra: "Extra active: hard training and a physical job"
            }
        }
    }
    var sex: Sex
    var age: Int
    var heightCm: Double
    var activity: Activity

    static let sexKey = "profileSex", ageKey = "profileAge", heightKey = "profileHeightCm", activityKey = "profileActivity"

    /// nil until sex, a plausible age and a plausible height are set.
    static func load(_ d: UserDefaults = .standard) -> MaintenanceProfile? {
        guard let sex = d.string(forKey: sexKey).flatMap(Sex.init(rawValue:)) else { return nil }
        let age = d.integer(forKey: ageKey), height = d.double(forKey: heightKey)
        guard (14...100).contains(age), (120.0...230.0).contains(height) else { return nil }
        return MaintenanceProfile(sex: sex, age: age, heightCm: height, activity: d.string(forKey: activityKey).flatMap(Activity.init(rawValue:)) ?? .light)
    }
}

enum Maintenance {
    static let kcalPerKgPerWeekAsDaily = 1100.0      // 7,700 kcal per kg, over seven days
    static let startAfterDays = 10                   // the sheet begins its estimate on the eleventh day of history
    static let weighInBlanksAllowed = 5              // of the last ten days
    static let calorieBlanksAllowed = 3              // of the last ten days
    static let plausible = 1000.0...6000.0

    /// Mifflin-St Jeor resting energy, times the activity factor.
    static func formulaEstimate(_ p: MaintenanceProfile, weightKg: Double) -> Int {
        let sexTerm: Double = p.sex == .male ? 5 : (p.sex == .female ? -161 : -78)
        let bmr = 10 * weightKg + 6.25 * p.heightCm - 5 * Double(p.age) + sexTerm
        return Int((bmr * p.activity.factor).rounded())
    }

    /// The daily series, from the first logged day through `end`.
    static func series(_ days: [DaySnapshot], through end: Date, smoothingDays: Int = 16, calendar cal: Calendar = .current) -> [MaintenancePoint] {
        let end0 = cal.startOfDay(for: end)
        let map = Dictionary(days.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        guard let first = days.filter({ $0.weightKg != nil || $0.calories != nil }).map({ cal.startOfDay(for: $0.date) }).min(), first <= end0 else { return [] }
        let alpha = Metrics.alpha(forDays: smoothingDays)
        let trend = Dictionary(Metrics.weightTrend(days, through: end0, smoothingDays: smoothingDays, calendar: cal)
            .map { (cal.startOfDay(for: $0.date), $0.trendKg) }, uniquingKeysWith: { a, _ in a })
        func back(_ n: Int, from d: Date) -> Date { cal.date(byAdding: .day, value: -n, to: d)! }
        let count = (cal.dateComponents([.day], from: first, to: end0).day ?? 0)
        var out: [MaintenancePoint] = []
        var intake: Double?, tdee: Double?
        for i in 0...count {
            let d = cal.date(byAdding: .day, value: i, to: first)!
            // Calories: a 14-day average of the days logged, smoothed, and carried over days with nothing logged.
            if map[d]?.calories != nil {
                let recent = (0..<14).compactMap { map[back($0, from: d)]?.calories }.map(Double.init)
                if !recent.isEmpty {
                    let avg = recent.reduce(0, +) / Double(recent.count)
                    intake = intake.map { alpha * avg + (1 - alpha) * $0 } ?? avg
                }
            }
            // Weekly change in trend weight, as an energy gap.
            var estimate: Double?
            if let t = trend[d], let t7 = trend[back(7, from: d)], let l = intake { estimate = l - (t - t7) * kcalPerKgPerWeekAsDaily }
            // Enough recent weigh-ins and calorie logs to trust a new reading?
            let weighBlanks = (0..<10).filter { map[back($0, from: d)]?.weightKg == nil }.count
            let calorieBlanks = (0..<10).filter { map[back($0, from: d)]?.calories == nil }.count
            let updating = weighBlanks <= weighInBlanksAllowed && calorieBlanks <= calorieBlanksAllowed
            if i >= startAfterDays, updating, let e = estimate { tdee = tdee.map { alpha * e + (1 - alpha) * $0 } ?? e }
            out.append(MaintenancePoint(date: d, tdee: tdee, intake: intake, status: updating ? .updating : .waiting))
        }
        return out
    }

    /// The estimate as of `end`: from the logs when they have built one, otherwise from the formula if a profile is set.
    static func estimate(_ days: [DaySnapshot], through end: Date, smoothingDays: Int = 16, profile: MaintenanceProfile? = nil,
                         calendar cal: Calendar = .current) -> MaintenanceEstimate? {
        let s = series(days, through: end, smoothingDays: smoothingDays, calendar: cal)
        let latestTrend = Metrics.weightTrend(days, through: end, smoothingDays: smoothingDays, calendar: cal).last?.trendKg
        let formula = profile.flatMap { p in latestTrend.map { formulaEstimate(p, weightKg: $0) } }
        if let last = s.last, let v = last.tdee, plausible.contains(v) {
            let readings = s.compactMap(\.tdee).count
            let confidence: DataConfidence = last.status == .updating ? (readings >= 14 ? .high : .medium) : .low
            return MaintenanceEstimate(kcalPerDay: Int(v.rounded()), source: .trend, status: last.status, confidence: confidence, series: s,
                                       formulaKcal: formula, intakeKcal: last.intake.map { Int($0.rounded()) })
        }
        if let f = formula {
            return MaintenanceEstimate(kcalPerDay: f, source: .formula, status: .waiting, confidence: .low, series: s,
                                       formulaKcal: f, intakeKcal: s.last?.intake.map { Int($0.rounded()) })
        }
        return nil
    }
}
