import Foundation
import SwiftData

/// A fitness campaign: cut, bulk or maintenance, with an optional target weight and length.
/// CloudKit-compatible like the other models (defaulted fields, no unique constraints).
/// See CampaignRules for how campaigns are numbered, started and ended.
@Model
final class Campaign {
    var id: UUID = UUID()
    var number: Int = 0
    var kindRaw: String = CampaignKind.maintenance.rawValue
    var isDefault: Bool = false
    var targetWeightKg: Double?
    var start: Date = Date()
    var plannedWeeks: Int?
    var end: Date?
    var endedEarly: Bool = false
    var label: String?                    // optional name chosen by the user
    var startWeightKg: Double?            // the weight the trend starts from on the campaign's first day
    var measureEveryDays: Int = 0         // body measurements every this many days from the start; 0 = off
    var photoPrompt: Bool = false         // ask about progress photos on the measurement days
    var updatedAt: Date = Date()

    init(_ info: CampaignInfo) {
        id = info.id
        number = info.number
        kindRaw = info.kind.rawValue
        isDefault = info.isDefault
        targetWeightKg = info.targetWeightKg
        start = info.start
        plannedWeeks = info.plannedWeeks
        end = info.end
        endedEarly = info.endedEarly
        label = info.label
        startWeightKg = info.startWeightKg
        measureEveryDays = info.measureEveryDays
        photoPrompt = info.photoPrompt
    }

    var info: CampaignInfo {
        CampaignInfo(id: id, number: number, kind: CampaignKind(rawValue: kindRaw) ?? .maintenance,
                     isDefault: isDefault, targetWeightKg: targetWeightKg, start: start,
                     plannedWeeks: plannedWeeks, end: end, endedEarly: endedEarly, label: label, startWeightKg: startWeightKg, measureEveryDays: measureEveryDays, photoPrompt: photoPrompt)
    }
}
