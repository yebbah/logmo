import SwiftUI

/// The two looks, chosen in Settings. All colours come from here so views never
/// hard-code them.
enum AppTheme: String, CaseIterable, Identifiable {
    case clean, midnight
    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: "Clean"
        case .midnight: "Midnight"
        }
    }

    var blurb: String {
        switch self {
        case .clean: "Light, white cards, iOS blue."
        case .midnight: "Dark navy, cyan accent."
        }
    }

    var scheme: ColorScheme { self == .clean ? .light : .dark }

    var bg: Color { self == .clean ? Color(hex: 0xF2F2F7) : Color(hex: 0x0B1220) }
    var card: Color { self == .clean ? Color(hex: 0xFFFFFF) : Color(hex: 0x141C2E) }
    var border: Color { self == .clean ? .clear : Color(hex: 0x243049) }
    var muted: Color { self == .clean ? Color(hex: 0x63636E) : Color(hex: 0x9AA7C2) }
    var accent: Color { self == .clean ? Color(hex: 0x0A64D6) : Color(hex: 0x5CC8FF) }
    /// Text/icons drawn on top of the accent colour.
    var onAccent: Color { self == .clean ? .white : Color(hex: 0x0B1220) }
    var good: Color { self == .clean ? Color(hex: 0x1E8E3E) : Color(hex: 0x4ADE80) }
    var bad: Color { self == .clean ? Color(hex: 0xD93025) : Color(hex: 0xFF7A7A) }
    var track: Color { self == .clean ? Color(hex: 0xE4E4EA) : Color(hex: 0x243049) }

    func color(for r: Rating) -> Color {
        let clean: [Rating: UInt32] = [.sleep: 0x5B4BDB, .fatigue: 0xE07B00, .stress: 0xD14343, .hunger: 0xB8960C,
                                       .performance: 0x1E8E3E, .appetite: 0xC2417A, .soreness: 0x8A5A2B]
        let night: [Rating: UInt32] = [.sleep: 0xA99BFF, .fatigue: 0xFFA94D, .stress: 0xFF8F8F, .hunger: 0xFFE066,
                                       .performance: 0x4ADE80, .appetite: 0xF783C0, .soreness: 0xE5B67A]
        return Color(hex: (self == .clean ? clean : night)[r] ?? 0x888888)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = AppTheme.clean }

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
