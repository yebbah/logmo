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

/// Shared tab selection, so a screen deep in one tab can send the user to another.
@Observable
final class AppNavigation {
    var tab = 0     // 0 Dashboard, 1 Streaks, 2 Log, 3 Campaigns, 4 Settings
    var openNewCampaign = false     // set when a prompt sends the user to Campaigns to start one
}

struct RootView: View {
    @AppStorage(SettingsKey.theme) private var themeRaw = AppTheme.clean.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .clean }

    // Debug aid for screenshots: -tab 0 Dashboard | 1 Streaks | 2 Log | 3 Campaigns | 4 Settings
    @State private var nav: AppNavigation = {
        let n = AppNavigation()
        #if DEBUG
        n.tab = UserDefaults.standard.integer(forKey: "tab")
        #endif
        return n
    }()

    /// The landing screen shows for three seconds on launch, then fades out. It is drawn alone first and
    /// the tabs are added a moment later, so the heavy first Dashboard render can't hold up the landing.
    @State private var showLanding = true
    @State private var showTabs = false

    var body: some View {
        #if DEBUG
        // Debug aid for screenshots: -debugScreen campaigns | newcampaign
        if let screen = UserDebug.screen {
            Group {
                switch screen {
                case "newcampaign": NewCampaignForm(minStart: Calendar.current.startOfDay(for: Date()))
                case "about": NavigationStack { Form { AboutSection().listRowBackground(theme.card) }.scrollContentBackground(.hidden).background(theme.bg).navigationTitle("Settings") }
                case "campaigndetail": DebugCampaignDetail().environment(AppNavigation())
                case "plan": DebugPlan()
                default: CampaignsView().environment(AppNavigation())
                }
            }
            .environment(\.theme, theme).preferredColorScheme(theme.scheme).tint(theme.accent)
        } else { withLanding }
        #else
        withLanding
        #endif
    }

    private var withLanding: some View {
        ZStack {
            if showTabs { tabs }
            if showLanding {
                LandingView()
                    .environment(\.theme, theme)
                    .preferredColorScheme(theme.scheme)
                    .transition(.opacity)
                    .zIndex(1)
                    .onTapGesture { skipLanding() }             // tap to skip
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))      // let the landing paint first
            showTabs = true
            try? await Task.sleep(for: .milliseconds(2700))     // three seconds in all
            skipLanding()
        }
    }

    private func skipLanding() {
        guard showLanding else { return }
        showTabs = true
        withAnimation(.easeInOut(duration: 0.7)) { showLanding = false }
    }

    private var tabs: some View {
        TabView(selection: Bindable(nav).tab) {
            DashboardView().tabItem { Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis") }.tag(0)
            StreaksView().tabItem { Label("Streaks", systemImage: "flame") }.tag(1)
            LogView().tabItem { Label("Log", systemImage: "square.and.pencil") }.tag(2)
            CampaignsView().tabItem { Label("Campaigns", systemImage: "flag.checkered") }.tag(3)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
        }
        .environment(nav)
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
    static let trackCycle = "trackCycle"
    static let reminderOn = "reminderOn"
    static let reminderWeekday = "reminderWeekday"
    static let reminderMinutes = "reminderMinutes"
}

#if DEBUG
enum UserDebug {
    static var screen: String? { UserDefaults.standard.string(forKey: "debugScreen") }
}
#endif
