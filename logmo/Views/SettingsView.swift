import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.theme) private var themeRaw = AppTheme.clean.rawValue
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @AppStorage(SettingsKey.required) private var requiredRaw = RequiredTrackers.defaultRaw
    @AppStorage(SettingsKey.trackCycle) private var trackCycle = false
    @AppStorage(SettingsKey.reminderOn) private var reminderOn = false
    @AppStorage(SettingsKey.reminderWeekday) private var reminderWeekday = Reminders.defaultWeekday
    @AppStorage(SettingsKey.reminderMinutes) private var reminderMinutes = Reminders.defaultMinutes
    @State private var reminderDenied = false
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false

    @Query(sort: \DayLog.day) private var logs: [DayLog]

    private var required: Set<Tracker> { RequiredTrackers.parse(requiredRaw) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    Picker("Theme", selection: $themeRaw) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text((AppTheme(rawValue: themeRaw) ?? .clean).blurb)
                        .font(.caption).foregroundStyle(theme.muted)
                } header: { Text("Appearance") }
                .listRowBackground(theme.card)
                Section {
                    ForEach(Tracker.allCases) { t in
                        Toggle(t.title, isOn: Binding(
                            get: { required.contains(t) },
                            set: { on in
                                var r = required
                                if on { r.insert(t) } else { r.remove(t) }
                                requiredRaw = RequiredTrackers.encode(r)
                            }))
                    }
                } header: { Text("Required for a complete day") } footer: {
                    Text("A day counts as complied when everything switched on here is fully logged, every daily goal is met, and the week's goals are on track: average calories, weekly-average steps and workout days. Food needs calories, protein, carbs and fat; check-in needs all seven ratings (training performance may be n/a).")
                }
                .listRowBackground(theme.card)
                Section("Units") {
                    Picker("Weight", selection: $unitRaw) {
                        ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Text("Weights are stored in kg, so switching never changes your data.")
                        .font(.caption).foregroundStyle(theme.muted)
                }
                .listRowBackground(theme.card)
                Section("Trend") {
                    Picker("Weight smoothing", selection: $smoothing) {
                        ForEach([7, 10, 14, 16, 20], id: \.self) { Text("\($0)-day").tag($0) }
                    }
                    Text("The workbook uses 16-day (male) or 20-day (female). Biofeedback lines use a fixed 7-day smoothing.")
                        .font(.caption).foregroundStyle(theme.muted)
                }
                .listRowBackground(theme.card)
                Section {
                    Toggle("Weekly plan reminder", isOn: Binding(
                        get: { reminderOn },
                        set: { on in
                            if on {
                                Task {
                                    if await Reminders.requestAuthorization() {
                                        reminderOn = true; reminderDenied = false
                                        await Reminders.schedule(weekday: reminderWeekday, minutes: reminderMinutes)
                                    } else { reminderOn = false; reminderDenied = true }
                                }
                            } else { reminderOn = false; Reminders.cancel() }
                        }))
                    .id("reminders")
                    if reminderOn {
                        Picker("Day", selection: $reminderWeekday) {
                            ForEach(Reminders.weekdays, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        DatePicker("Time", selection: Binding(
                            get: { Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: Date()) ?? Date() },
                            set: { d in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                                reminderMinutes = (c.hour ?? 18) * 60 + (c.minute ?? 0)
                            }), displayedComponents: .hourAndMinute)
                    }
                    if reminderDenied {
                        Text("Notifications are turned off for logmo in iOS Settings.").font(.footnote).foregroundStyle(theme.bad)
                        Button("Open iOS Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
                            .font(.footnote)
                    }
                } header: { Text("Reminders") } footer: {
                    Text("A notification once a week, at the day and time you choose, to plan the week ahead. It says only \"Plan your week\", nothing from your logs.")
                }
                .listRowBackground(theme.card)

                Section {
                    Toggle("Track my menstrual cycle", isOn: $trackCycle)
                } header: { Text("Cycle") } footer: {
                    Text("Adds a daily \"on your period?\" question to the Log screen. Days you mark yes show as red dots on the weigh-in and the trend. Optional: it never counts against compliance. Stored only on this iPhone.")
                }
                .listRowBackground(theme.card)

                Section("Connections") {
                    LabeledContent("Apple Health", value: "Not yet available")
                    LabeledContent("Cloud sync", value: "Not yet available")
                }
                .listRowBackground(theme.card)
                Section {
                    ShareLink(item: CSVDocument(text: CSVExport.render(logs.map(\.exportRow))),
                              preview: SharePreview("logmo-export.csv")) {
                        Label("Export data as CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(logs.isEmpty)
                } header: { Text("Backup") } footer: {
                    Text("Data lives only on this iPhone. Export saves daily logs (not goals or campaigns) as a copy you can keep in Files or iCloud Drive.")
                }
                .listRowBackground(theme.card)
                AboutSection()
                    .listRowBackground(theme.card)
                Section {
                    Button("Delete all data", role: .destructive) { confirmDelete = true }
                } footer: { Text("Deletes logs, goals and campaign history. Data is stored only on this iPhone.") }
                .listRowBackground(theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .onAppear {
                #if DEBUG
                // Debug aid for screenshots: -scrollTo reminders
                if let id = UserDefaults.standard.string(forKey: "scrollTo") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(id, anchor: .top) }
                }
                #endif
            }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete every log, goal and campaign on this iPhone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    try? context.delete(model: DayLog.self)
                    try? context.delete(model: WeekGoal.self)
                    try? context.delete(model: Campaign.self)
                    try? context.save()
                }
            }
        }
    }
}

/// Settings → About: logo, version and how to contact the developer.
struct AboutSection: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        Section("About") {
            HStack(spacing: 14) {
                LogoMark(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("logmo").font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text("Track progress with clarity").font(.caption).foregroundStyle(theme.muted)
                }
            }
            .padding(.vertical, 4)
            LabeledContent("Version", value: AppInfo.versionString)
            Button {
                openURL(AppInfo.contactURL(osVersion: UIDevice.current.systemVersion))
            } label: {
                Label("Contact the developer", systemImage: "envelope")
            }
            HStack {
                Text(AppInfo.developerEmail).font(.footnote).foregroundStyle(theme.muted).textSelection(.enabled)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = AppInfo.developerEmail
                    copied = true
                }
                .font(.footnote).buttonStyle(.borderless)
            }
        }
    }
}
