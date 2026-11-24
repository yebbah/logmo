import SwiftUI
import SwiftData

@main
struct LogmoApp: App {
    let container: ModelContainer = {
        // Local only. To enable iCloud later: add the CloudKit capability and
        // change `.none` to `.automatic`. The model is already CloudKit-compatible.
        let config = ModelConfiguration(cloudKitDatabase: .none)
        do { return try ModelContainer(for: DayLog.self, configurations: config) }
        catch { fatalError("Could not open the local store: \(error)") }
    }()

    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(container)
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis") }
            LogView().tabItem { Label("Log", systemImage: "square.and.pencil") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

enum SettingsKey {
    static let unit = "weightUnit"
    static let smoothing = "smoothingDays"
}
