import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage(SettingsKey.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(SettingsKey.smoothing) private var smoothing = 16
    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Weight", selection: $unitRaw) {
                        ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Text("Weights are stored in kg, so switching never changes your data.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Trend") {
                    Picker("Smoothing", selection: $smoothing) {
                        ForEach([7, 10, 14, 16, 20], id: \.self) { Text("\($0)-day").tag($0) }
                    }
                    Text("The workbook uses 16-day (male) or 20-day (female).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Connections") {
                    LabeledContent("Apple Health", value: "Not yet available")
                    LabeledContent("Cloud sync", value: "Not yet available")
                }
                Section {
                    Button("Delete all data", role: .destructive) { confirmDelete = true }
                } footer: { Text("Data is stored only on this iPhone.") }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete every log on this iPhone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    try? context.delete(model: DayLog.self); try? context.save()
                }
            }
        }
    }
}
