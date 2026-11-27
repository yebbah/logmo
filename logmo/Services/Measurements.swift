import Foundation

/// Body measurements: typed in, in centimetres, on the days a campaign asks for them (or any day). Never read from Apple Health.
enum MeasureSite: String, CaseIterable, Identifiable, Codable {
    case navel, belowNavel, aboveNavel, chest, thighs, calves, biceps
    var id: String { rawValue }

    var title: String {
        switch self {
        case .navel: "Waist at navel"
        case .belowNavel: "Waist 2 in below navel"
        case .aboveNavel: "Waist 2 in above navel"
        case .chest: "Chest"
        case .thighs: "Thighs"
        case .calves: "Calves"
        case .biceps: "Biceps"
        }
    }
    /// A short name for chart legends and tables.
    var short: String {
        switch self {
        case .navel: "Navel"
        case .belowNavel: "2 in below"
        case .aboveNavel: "2 in above"
        case .chest: "Chest"
        case .thighs: "Thighs"
        case .calves: "Calves"
        case .biceps: "Biceps"
        }
    }
    var hint: String? { self == .biceps ? "relaxed" : (self == .belowNavel || self == .aboveNavel ? "about 5 cm" : nil) }
    var isWaist: Bool { self == .navel || self == .belowNavel || self == .aboveNavel }
}

/// One day's measurements, kept as a small text on the day's log ("navel:83.5,chest:97") so the log stays one row per day.
struct BodyMeasures: Equatable {
    var values: [MeasureSite: Double] = [:]
    var isEmpty: Bool { values.isEmpty }

    init(values: [MeasureSite: Double] = [:]) { self.values = values }

    init(raw: String?) {
        for part in (raw ?? "").split(separator: ",") {
            let kv = part.split(separator: ":")
            if kv.count == 2, let s = MeasureSite(rawValue: String(kv[0])), let v = Double(kv[1]), v > 0 { values[s] = v }
        }
    }

    var raw: String? {
        let parts = MeasureSite.allCases.compactMap { s in values[s].map { "\(s.rawValue):\(String(format: "%.1f", $0))" } }
        return parts.isEmpty ? nil : parts.joined(separator: ",")
    }

    /// Plausible tape readings: more than 5 cm and under 300 cm.
    static func isPlausible(_ v: Double) -> Bool { v > 5 && v < 300 }
}

/// How often a campaign asks for measurements. Monthly means every four weeks.
enum MeasureCadence: Int, CaseIterable, Identifiable {
    case off = 0, weekly = 7, biweekly = 14, monthly = 28
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .weekly: "Weekly"
        case .biweekly: "Biweekly"
        case .monthly: "Monthly"
        }
    }
    init(days: Int) { self = MeasureCadence(rawValue: days) ?? .off }
}

struct MeasureEntry: Equatable {
    var day: Date
    var values: [MeasureSite: Double]
}

enum MeasureRules {
    /// The days a campaign asks for measurements: its first day, then every cadence, up to `through` and the campaign's last day.
    static func dueDates(_ c: CampaignInfo, through: Date, calendar cal: Calendar = .current) -> [Date] {
        guard c.measureEveryDays > 0 else { return [] }
        let limit = min(cal.startOfDay(for: through), CampaignRules.lastDay(c, calendar: cal) ?? cal.startOfDay(for: through))
        var out: [Date] = []
        var d = c.start
        while d <= limit {
            out.append(d)
            d = cal.date(byAdding: .day, value: c.measureEveryDays, to: d)!
        }
        return out
    }

    /// Due when the campaign asks for measurements, today is inside it, and nothing has been measured since the latest due date.
    static func isDue(_ c: CampaignInfo, entries: [MeasureEntry], today: Date, calendar cal: Calendar = .current) -> Bool {
        guard c.measureEveryDays > 0, CampaignRules.contains(c, day: today, calendar: cal),
              let latest = dueDates(c, through: today, calendar: cal).last else { return false }
        return !entries.contains { cal.startOfDay(for: $0.day) >= latest && cal.startOfDay(for: $0.day) <= cal.startOfDay(for: today) }
    }

    /// The next due date after today, nil when off or none is left inside the campaign.
    static func nextDue(_ c: CampaignInfo, today: Date, calendar cal: Calendar = .current) -> Date? {
        guard c.measureEveryDays > 0 else { return nil }
        let last = CampaignRules.lastDay(c, calendar: cal)
        var d = c.start
        while d <= cal.startOfDay(for: today) { d = cal.date(byAdding: .day, value: c.measureEveryDays, to: d)! }
        return last.map { d <= $0 } ?? true ? d : nil
    }

    /// The entries inside a campaign (up to `through`, when given), oldest first.
    static func entries(_ all: [MeasureEntry], in c: CampaignInfo, through: Date? = nil, calendar cal: Calendar = .current) -> [MeasureEntry] {
        all.filter { e in
            let d = cal.startOfDay(for: e.day)
            return CampaignRules.contains(c, day: d, calendar: cal) && (through.map { d <= cal.startOfDay(for: $0) } ?? true)
        }.sorted { $0.day < $1.day }
    }

    /// A site's readings, oldest first.
    static func series(_ entries: [MeasureEntry], _ s: MeasureSite) -> [(day: Date, cm: Double)] {
        entries.compactMap { e in e.values[s].map { (e.day, $0) } }.sorted { $0.day < $1.day }
    }

    /// Latest reading minus the first, per site, needing two readings at least a week apart.
    static func changes(_ entries: [MeasureEntry], calendar cal: Calendar = .current) -> [MeasureSite: Double] {
        var out: [MeasureSite: Double] = [:]
        for s in MeasureSite.allCases {
            let ser = series(entries, s)
            if let a = ser.first, let b = ser.last, (cal.dateComponents([.day], from: a.day, to: b.day).day ?? 0) >= 7 { out[s] = b.cm - a.cm }
        }
        return out
    }
}
