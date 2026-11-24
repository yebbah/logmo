import SwiftUI

/// Central place for colours so a theme can be swapped in later.
enum Theme {
    static func color(for r: Rating) -> Color {
        switch r {
        case .sleep: .indigo
        case .fatigue: .orange
        case .stress: .red
        case .hunger: .yellow
        case .performance: .green
        case .appetite: .pink
        case .soreness: .brown
        }
    }
    static let good = Color.green
    static let bad = Color.red
    static let neutral = Color.secondary.opacity(0.35)
}
