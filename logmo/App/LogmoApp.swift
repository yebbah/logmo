import SwiftUI
import SwiftData

@main
struct LogmoApp: App {
    let container: ModelContainer = {
        // Local only. To enable iCloud later: add the CloudKit capability and
        // change `.none` to `.automatic`. The model is already CloudKit-compatible.
        #if DEBUG
        if DemoData.enabled {
            let mem = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            if let c = try? ModelContainer(for: DayLog.self, WeekGoal.self, configurations: mem) {
                DemoData.seed(c.mainContext)
                return c
            }
        }
        #endif
        let config = ModelConfiguration(cloudKitDatabase: .none)
        do { return try ModelContainer(for: DayLog.self, WeekGoal.self, configurations: config) }
        catch { fatalError("Could not open the local store: \(error)") }
    }()

    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(container)
    }
}

struct RootView: View {
    // Debug aid for screenshots: -tab 0|1|2
    @AppStorage(SettingsKey.theme) private var themeRaw = AppTheme.clean.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .clean }

    @State private var tab: Int = {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "tab")
        #else
        return 0
        #endif
    }()

    var body: some View {
        TabView(selection: $tab) {
            DashboardView().tabItem { Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis") }.tag(0)
            LogView().tabItem { Label("Log", systemImage: "square.and.pencil") }.tag(1)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .environment(\.theme, theme)
        .preferredColorScheme(theme.scheme)
        .tint(theme.accent)
    }
}

enum SettingsKey {
    static let unit = "weightUnit"
    static let smoothing = "smoothingDays"
    static let required = "requiredTrackers"
    static let bioOverlay = "bioOverlayOn"
    static let bioShown = "bioShown"
    static let theme = "theme"
}
