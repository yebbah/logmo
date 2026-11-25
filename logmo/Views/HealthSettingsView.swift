import SwiftUI
import SwiftData

/// Settings → Apple Health: connect, choose what to bring in, update now. logmo only reads from Health.
struct HealthSettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage(HealthSettings.connected) private var connected = false
    @State private var syncing = false
    @State private var lastSync: Date? = HealthSync.lastSync
    @State private var failed = false

    private func binding(_ t: HealthTopic) -> Binding<Bool> {
        Binding(get: { HealthSettings.isOn(t) }, set: { on in UserDefaults.standard.set(on, forKey: HealthSettings.key(t)); if on { update() } })
    }

    var body: some View {
        Form {
            Section {
                Text("logmo only **reads** from Health and never writes to it. Pick what to bring in. Anything you type yourself always wins over an imported value, and everything stays on this iPhone.")
                    .font(.footnote).foregroundStyle(theme.muted)
            }
            .listRowBackground(theme.card)

            if !AppleHealth.isAvailable {
                Section { Text("Apple Health isn't available on this device.").foregroundStyle(theme.muted) }.listRowBackground(theme.card)
            } else if !connected {
                Section {
                    Button { connect() } label: { Text("Connect Apple Health").fontWeight(.semibold).frame(maxWidth: .infinity) }
                    if failed { Text("Couldn't connect. Try again, or check Health in iOS Settings.").font(.footnote).foregroundStyle(theme.bad) }
                } footer: { Text("iOS then asks which types logmo may read, one at a time.") }
                .listRowBackground(theme.card)
            } else {
                Section {
                    ForEach(HealthTopic.allCases) { t in
                        Toggle(isOn: binding(t)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title)
                                Text(t.detail).font(.caption).foregroundStyle(theme.muted)
                            }
                        }
                    }
                } header: { Text("Bring in") } footer: {
                    Text("Steps and food keep updating while the day is open. Values already imported stay if you switch a type off.")
                }
                .listRowBackground(theme.card)

                Section {
                    HStack {
                        Text(lastSync.map { "Updated \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Not updated yet")
                            .font(.subheadline)
                        Spacer()
                        Button { update() } label: { if syncing { ProgressView() } else { Text("Update now") } }
                            .buttonStyle(.borderless).disabled(syncing)
                    }
                } footer: {
                    Text("logmo also updates when it opens and on the Log screen. iOS asks permission one type at a time, and a type you decline looks the same as no data. If something is missing, open Health → Sharing → Apps → logmo.")
                }
                .listRowBackground(theme.card)

                Section {
                    Button("Open Health settings") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
                    Button("Disconnect", role: .destructive) { connected = false }
                } footer: { Text("Disconnecting stops updates. Values already imported stay in your logs.") }
                .listRowBackground(theme.card)
            }

            Section {
                ForEach(["Sleep hours", "Cycle", "Resting heart rate and HRV", "Body fat and lean mass"], id: \.self) { Text($0).foregroundStyle(theme.muted) }
            } header: { Text("Later") } footer: { Text("Planned, not in this version.") }
            .listRowBackground(theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func connect() {
        Task {
            do {
                try await AppleHealth.requestAuthorization()
                connected = true; failed = false
                update()
            } catch { failed = true }
        }
    }

    private func update() {
        guard !syncing else { return }
        syncing = true
        Task {
            await HealthSync.sync(context, force: true)
            lastSync = HealthSync.lastSync
            syncing = false
        }
    }
}
