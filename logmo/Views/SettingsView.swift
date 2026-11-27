import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.theme) private var themeRaw = AppTheme.clean.rawValue
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @AppStorage(SettingsKey.required) private var requiredRaw = RequiredTrackers.defaultRaw
    @AppStorage(SettingsKey.trackCycle) private var trackCycle = false
    @AppStorage(SettingsKey.trackSick) private var trackSick = false
    @AppStorage(MaintenanceProfile.sexKey) private var profileSex = ""
    @AppStorage(MaintenanceProfile.ageKey) private var profileAge = 0
    @AppStorage(MaintenanceProfile.heightKey) private var profileHeight = 0.0
    @AppStorage(MaintenanceProfile.activityKey) private var profileActivity = MaintenanceProfile.Activity.light.rawValue
    @AppStorage(SettingsKey.reminderOn) private var reminderOn = false
    @AppStorage(SettingsKey.reminderWeekday) private var reminderWeekday = Reminders.defaultWeekday
    @AppStorage(SettingsKey.reminderMinutes) private var reminderMinutes = Reminders.defaultMinutes
    @AppStorage(SettingsKey.dailyReminderOn) private var dailyOn = false
    @AppStorage(SettingsKey.pace) private var paceRaw = SuggestionPace.conservative.rawValue
    @AppStorage(SettingsKey.dailyReminderMinutes) private var dailyMinutes = DailyReminderRules.defaultMinutes
    @AppStorage(HealthSettings.connected) private var healthConnected = false
    @State private var reminderDenied = false
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false
    @State private var deleteError: String?
    @Query private var campaigns: [Campaign]
    @Query private var weekGoals: [WeekGoal]
    @State private var pickBackup = false
    @State private var pendingRestore: BackupFile?

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
                Section {
                    Picker("Sex", selection: $profileSex) {
                        Text("Not set").tag("")
                        ForEach(MaintenanceProfile.Sex.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    LabeledContent("Age") {
                        TextField("years", value: $profileAge, format: .number.grouping(.never)).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Height (cm)") {
                        TextField("cm", value: $profileHeight, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Activity", selection: $profileActivity) {
                        ForEach(MaintenanceProfile.Activity.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } header: { Text("About you (optional)") } footer: {
                    Text("Used only for a formula estimate of your maintenance calories until your own weight and calorie logs have built one, and to cross-check it. Stored only on this iPhone and never sent anywhere. The estimate is a starting point, not advice.")
                }
                .listRowBackground(theme.card)

                Section {
                    Picker("Preferred pace", selection: $paceRaw) {
                        ForEach(SuggestionPace.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented)
                } header: { Text("Weekly suggestion") } footer: {
                    Text("The weekly suggestion shows both a conservative and an aggressive option when the data supports a faster one. Your preference decides which is selected first and which one Apple Intelligence writes about. Conservative: a smaller, easier-to-keep change. Aggressive: a faster change that is harder to sustain. The safety limits are the same for both.")
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
                    Toggle("Daily log reminder", isOn: Binding(
                        get: { dailyOn },
                        set: { on in
                            if on {
                                Task {
                                    if await Reminders.requestAuthorization() {
                                        dailyOn = true; reminderDenied = false
                                        await DailyReminder.refresh(context)
                                    } else { dailyOn = false; reminderDenied = true }
                                }
                            } else { dailyOn = false; Task { await DailyReminder.cancelAll() } }
                        }))
                    if dailyOn {
                        DatePicker("Daily time", selection: Binding(
                            get: { Calendar.current.date(bySettingHour: dailyMinutes / 60, minute: dailyMinutes % 60, second: 0, of: Date()) ?? Date() },
                            set: { d in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                                dailyMinutes = (c.hour ?? 20) * 60 + (c.minute ?? 0)
                                Task { await DailyReminder.refresh(context) }
                            }), displayedComponents: .hourAndMinute)
                    }
                    if reminderDenied {
                        Text("Notifications are turned off for logmo in iOS Settings.").font(.footnote).foregroundStyle(theme.bad)
                        Button("Open iOS Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
                            .font(.footnote)
                    }
                } header: { Text("Reminders") } footer: {
                    Text("The weekly reminder is a notification once a week, at the day and time you choose, to plan the week ahead. The daily one comes at your chosen time, but only on days you haven't finished your daily goals (weigh-in, protein, steps, water; or your required trackers if you set no daily goals). Log what's needed and today's is cancelled. They say only \"Plan your week\" and \"Time to log\", nothing from your logs.")
                }
                .listRowBackground(theme.card)

                Section {
                    Toggle("Track my menstrual cycle", isOn: $trackCycle)
                } header: { Text("Cycle") } footer: {
                    Text("Adds a daily \"on your period?\" question to the Log screen. Days you mark yes show as red dots on the weigh-in and the trend. Optional: it never counts against compliance. Stored only on this iPhone.")
                }
                .listRowBackground(theme.card)

                Section {
                    Toggle("Track when I'm sick", isOn: $trackSick)
                } header: { Text("Health") } footer: {
                    Text("Adds a daily \"are you sick today?\" question to the Log screen. Days you mark yes show as yellow dots on the weigh-in and the trend. Optional: it never counts against compliance. Stored only on this iPhone.")
                }
                .listRowBackground(theme.card)

                Section("Connections") {
                    NavigationLink {
                        HealthSettingsView()
                    } label: {
                        LabeledContent("Apple Health", value: healthConnected ? "Connected" : "Off")
                    }
                    LabeledContent("Cloud sync", value: "Not yet available")
                }
                .listRowBackground(theme.card)
                Section {
                    let rows = ExportBuilder.dayRows(logs: logs, campaigns: campaigns, goals: weekGoals)
                    ShareLink(item: ExportBuilder.file("logmo-daily-logs.csv", CSVExport.render(rows))) {
                        Label("Export daily logs (CSV)", systemImage: "tablecells")
                    }
                    .disabled(logs.isEmpty)
                    ShareLink(item: ExportBuilder.file("logmo-campaigns.csv", CSVExport.campaignsCSV(campaigns.map(\.info)))) {
                        Label("Export campaigns (CSV)", systemImage: "flag.checkered")
                    }
                    ShareLink(item: ExportBuilder.file("logmo-weekly-goals.csv", CSVExport.weeklyGoalsCSV(ExportBuilder.goalRows(campaigns: campaigns, goals: weekGoals)))) {
                        Label("Export weekly goals (CSV)", systemImage: "target")
                    }
                    if let data = try? Backup.encode(Backup.make(context)) {
                        ShareLink(item: BackupDocument(data: data), preview: SharePreview("logmo-backup.json")) {
                            Label("Save a full backup", systemImage: "externaldrive.badge.icloud")
                        }
                    }
                    Button { pickBackup = true } label: { Label("Restore from a backup", systemImage: "arrow.counterclockwise") }
                } header: { Text("Backup") } footer: {
                    Text("Data lives only on this iPhone. The full backup is everything in one file: every log, weekly goals, campaigns and your settings (units, theme, required trackers, reminder, cycle). Keep it in Files or iCloud Drive; restoring replaces what is on the phone. The three CSV exports are for spreadsheets: daily logs (with each day's campaign and goals), campaigns, and weekly goals.")
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
            .keyboardDismissible()
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
            .fileImporter(isPresented: $pickBackup, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do { pendingRestore = try Backup.decode(Data(contentsOf: url)) }
                catch { deleteError = "That file isn't a logmo backup." }
            }
            .confirmationDialog("Replace everything on this iPhone with the backup?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }), titleVisibility: .visible) {
                Button("Restore", role: .destructive) {
                    if let f = pendingRestore { do { try Backup.restore(f, into: context) } catch { deleteError = error.localizedDescription } }
                    pendingRestore = nil
                }
            } message: { Text(pendingRestore.map { "\($0.logs.count) days, \($0.campaigns.count) campaigns, \($0.goals.count) weekly goal sets." } ?? "") }
            .alert("Something went wrong", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(deleteError ?? "") }
            .confirmationDialog("Delete every log, goal and campaign on this iPhone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    do { try DataReset.deleteAll(context) }
                    catch { deleteError = error.localizedDescription }
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
