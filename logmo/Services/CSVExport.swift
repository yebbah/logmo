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
}

enum CSVExport {
    static let ratingColumns = ["sleep", "fatigue", "stress", "hunger", "performance", "appetite", "soreness"]
    static let header = (["date", "weight_kg", "calories_kcal", "protein_g", "fat_g", "carbs_g", "water_ml", "steps"] + ratingColumns + ["performance_na", "on_period"])
        .joined(separator: ",")

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
