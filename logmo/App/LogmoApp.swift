import SwiftUI
import SwiftData

@main
struct LogmoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let container: ModelContainer = {
        // Local only. To enable iCloud later: add the CloudKit capability and
        // change `.none` to `.automatic`. The model is already CloudKit-compatible.
        #if DEBUG
        if DemoData.enabled {
            let mem = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            if let c = try? ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self, configurations: mem) {
                DemoData.seed(c.mainContext)
                return c
            }
        }
        #endif
        let config = ModelConfiguration(cloudKitDatabase: .none)
        do { return try ModelContainer(for: DayLog.self, WeekGoal.self, Campaign.self, configurations: config) }
        catch { fatalError("Could not open the local store: \(error)") }
    }()

    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(container)
    }
}

struct RootView: View {
    // Debug aid for screenshots: -tab 0 Dashboard | 1 Streaks | 2 Log | 3 Settings
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
        #if DEBUG
        // Debug aid for screenshots: -debugScreen campaigns | newcampaign
        if let screen = UserDebug.screen {
            Group {
                switch screen {
                case "newcampaign": NewCampaignForm(minStart: Calendar.current.startOfDay(for: Date()))
                case "goals": NavigationStack { CurrentGoalsEditor() }
                default: NavigationStack { CampaignsView() }
                }
            }
            .environment(\.theme, theme).preferredColorScheme(theme.scheme).tint(theme.accent)
        } else { tabs }
        #else
        tabs
        #endif
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            DashboardView().tabItem { Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis") }.tag(0)
            StreaksView().tabItem { Label("Streaks", systemImage: "flame") }.tag(1)
            LogView().tabItem { Label("Log", systemImage: "square.and.pencil") }.tag(2)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
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

#if DEBUG
enum UserDebug {
    static var screen: String? { UserDefaults.standard.string(forKey: "debugScreen") }
}
#endif
