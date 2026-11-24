import Foundation

/// Which trackers must be fully logged for a day to count as complied.
/// Stored as a comma-separated string so it works with @AppStorage.
enum RequiredTrackers {
    static let defaultRaw = Tracker.allCases.map(\.rawValue).joined(separator: ",")

    static func parse(_ raw: String) -> Set<Tracker> {
        Set(raw.split(separator: ",").compactMap { Tracker(rawValue: String($0)) })
    }

    static func encode(_ set: Set<Tracker>) -> String {
        Tracker.allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
    }
}
