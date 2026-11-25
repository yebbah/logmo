import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Plain-value copy of a day for export. Keeps CSV rendering free of SwiftData.
struct ExportRow: Equatable {
    var day: Date
    var weightKg: Double?
    var calories: Int?
    var proteinG: Int?
    var fatG: Int?
    var carbsG: Int?
    var waterMl: Int?
    var steps: Int?
    var ratings: [String: Int]      // keyed by Rating.rawValue
    var performanceNA: Bool = false
    var onPeriod: Bool?
    var isSick: Bool?
    // Context for the day, so the file stands on its own: the campaign it belongs to and that week's goals.
    var campaignNumber: Int?
    var campaign: String = ""
    var campaignKind: String = ""
    var goals: GoalSet?
}

enum CSVExport {
    static let ratingColumns = ["sleep", "fatigue", "stress", "hunger", "performance", "appetite", "soreness"]
    static let header = (["date", "weight_kg", "calories_kcal", "protein_g", "fat_g", "carbs_g", "water_ml", "steps"] + ratingColumns + ["performance_na", "on_period", "sick", "campaign_number", "campaign", "campaign_kind",
                                                                                       "goal_calories_per_day", "goal_calories_basis", "goal_protein_g", "goal_steps", "goal_steps_basis",
                                                                                       "goal_water_ml", "goal_workout_days"])
        .joined(separator: ",")

    static func quote(_ t: String) -> String {
        t.contains(",") || t.contains("\"") || t.contains("\n") ? "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : t
    }

    /// calories per day, basis, protein, steps, steps basis, water, workout days
    static func goalCells(_ g: GoalSet?) -> [String] {
        guard let g else { return Array(repeating: "", count: 7) }
        func c(_ v: Int?) -> String { v.map(String.init) ?? "" }
        return [c(g.caloriesWeekly.map { Int((Double($0) / 7).rounded()) }), g.caloriesWeekly == nil ? "" : (g.caloriesAtOrUnder ? "at_or_under" : "at_least"),
                c(g.proteinDaily), c(g.stepsDaily), g.stepsDaily == nil ? "" : (g.stepsIsWeeklyAverage ? "weekly_average" : "each_day"),
                c(g.waterDailyMl), c(g.workoutDaysWeekly)]
    }

    static func isoDay(_ d: Date, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// One line per campaign, oldest first.
    static func campaignsCSV(_ campaigns: [CampaignInfo], calendar cal: Calendar = .current) -> String {
        let head = "number,name,kind,automatic_default,target_weight_kg,start,planned_weeks,end,ended_early"
        let lines = campaigns.sorted { $0.number < $1.number }.map { c in
            [String(c.number), quote(c.label ?? c.title), c.kind.rawValue, c.isDefault ? "true" : "false",
             c.targetWeightKg.map { String(format: "%.1f", $0) } ?? "", isoDay(c.start, cal), c.plannedWeeks.map(String.init) ?? "",
             c.end.map { isoDay($0, cal) } ?? "", c.endedEarly ? "true" : "false"].joined(separator: ",")
        }
        return ([head] + lines).joined(separator: "\n") + "\n"
    }

    /// One line per campaign-week of weekly goals.
    static func weeklyGoalsCSV(_ goals: [(campaign: CampaignInfo?, week: Date, goals: GoalSet, confirmed: Bool)],
                               calendar cal: Calendar = .current) -> String {
        let head = "campaign_number,campaign,week_start,goal_calories_per_day,goal_calories_basis,goal_protein_g,goal_steps,goal_steps_basis,goal_water_ml,goal_workout_days,set_by_you"
        let lines = goals.sorted { ($0.campaign?.number ?? 0, $0.week) < ($1.campaign?.number ?? 0, $1.week) }.map { g in
            ([g.campaign.map { String($0.number) } ?? "", quote(g.campaign.map { $0.label ?? $0.title } ?? ""), isoDay(g.week, cal)]
             + goalCells(g.goals) + [g.confirmed ? "true" : "false"]).joined(separator: ",")
        }
        return ([head] + lines).joined(separator: "\n") + "\n"
    }

    /// One line per day, oldest first. Missing values are empty cells, never 0.
    /// Dates are local-calendar yyyy-MM-dd. Weight is always kg (the stored unit).
    static func render(_ rows: [ExportRow], calendar cal: Calendar = .current) -> String {
        func date(_ d: Date) -> String {
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        }
        func cell(_ v: Int?) -> String { v.map(String.init) ?? "" }
        var lines: [String] = []
        for r in rows.sorted(by: { $0.day < $1.day }) {
            var fields: [String] = [date(r.day)]
            fields.append(r.weightKg.map { String(format: "%.3f", $0) } ?? "")
            fields.append(cell(r.calories))
            fields.append(cell(r.proteinG))
            fields.append(cell(r.fatG))
            fields.append(cell(r.carbsG))
            fields.append(cell(r.waterMl))
            fields.append(cell(r.steps))
            for key in ratingColumns { fields.append(cell(r.ratings[key])) }
            fields.append(r.performanceNA ? "true" : "")
            fields.append(r.onPeriod.map { $0 ? "true" : "false" } ?? "")
            fields.append(r.isSick.map { $0 ? "true" : "false" } ?? "")
            fields.append(cell(r.campaignNumber)); fields.append(quote(r.campaign)); fields.append(r.campaignKind)
            fields.append(contentsOf: goalCells(r.goals))
            lines.append(fields.joined(separator: ","))
        }
        return ([header] + lines).joined(separator: "\n") + "\n"
    }
}

/// Lets SwiftUI's ShareLink offer the CSV as a file.
struct CSVDocument: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName("logmo-export.csv")
    }
}

/// Builds the three export files from the stored data.
@MainActor
enum ExportBuilder {
    static func dayRows(logs: [DayLog], campaigns: [Campaign], goals: [WeekGoal]) -> [ExportRow] {
        let infos = campaigns.map(\.info)
        let timeline = GoalTimeline(goals, campaigns: infos)
        return logs.map { l in
            var r = l.exportRow
            if let c = CampaignRules.campaign(for: l.day, in: infos) {
                r.campaignNumber = c.number; r.campaign = c.label ?? c.title; r.campaignKind = c.kind.rawValue
            }
            r.goals = timeline.goals(forDay: l.day)
            return r
        }
    }

    static func goalRows(campaigns: [Campaign], goals: [WeekGoal]) -> [(campaign: CampaignInfo?, week: Date, goals: GoalSet, confirmed: Bool)] {
        let byID = Dictionary(campaigns.map { ($0.id, $0.info) }, uniquingKeysWith: { a, _ in a })
        return goals.map { (campaign: $0.campaignID.flatMap { byID[$0] }, week: $0.weekStart, goals: $0.goalSet, confirmed: $0.confirmed) }
    }

    /// Writes a file in the temporary folder so the share sheet offers it under the right name.
    static func file(_ name: String, _ text: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? Data(text.utf8).write(to: url, options: .atomic)
        return url
    }
}
