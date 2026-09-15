import Foundation
import PDFKit
import SwiftUI

struct PDFAnalysisRow: Identifiable, Codable {
    let id: UUID
    var article: String
    var quantity: Int
    var unitPrice: Double?
    var total: Double?

    init(id: UUID = UUID(), article: String, quantity: Int, unitPrice: Double? = nil, total: Double? = nil) {
        self.id = id
        self.article = article
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.total = total
    }
}

struct PDFAnalysisDay: Identifiable, Codable {
    let id: UUID
    var date: Date
    var rows: [PDFAnalysisRow]

    init(id: UUID = UUID(), date: Date, rows: [PDFAnalysisRow]) {
        self.id = id
        self.date = date
        self.rows = rows
    }
}

struct PDFAnalysisResult: Identifiable, Codable {
    let id: UUID
    var fileName: String
    var date: Date?
    var rows: [PDFAnalysisRow]
    var days: [PDFAnalysisDay]

    init(id: UUID = UUID(), fileName: String, date: Date?, rows: [PDFAnalysisRow], days: [PDFAnalysisDay] = []) {
        self.id = id
        self.fileName = fileName
        self.date = date
        self.rows = rows
        self.days = days
    }
}

final class PDFAnalysisStore: ObservableObject {
    @Published private(set) var analyses: [PDFAnalysisResult] = []
    private let key = "contabilita_pdf_analisi"

    init() { carica() }

    func carica() {
        if let data = UserDefaults.standard.data(forKey: key),
           let value = try? JSONDecoder().decode([PDFAnalysisResult].self, from: data) {
            analyses = value
        }
    }

    func analizza(file: URL, bollette: [Bolletta]) {
        let ext = file.pathExtension.lowercased()
        if ext == "xlsx" || ext == "xls" {
            guard let excelDays = ExcelAnalysis.analizza(file: file) else { return }
            let days = excelDays.map { PDFAnalysisDay(date: $0.date, rows: $0.rows) }
            let result = PDFAnalysisResult(
                fileName: file.lastPathComponent,
                date: days.first?.date,
                rows: days.flatMap { $0.rows },
                days: days
            )
            salva(result)
            return
        }

        guard let document = PDFDocument(url: file) else { return }
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        let date = estraiData(text)
        let rows = estraiRighe(text)
        let days = date.map { [PDFAnalysisDay(date: $0, rows: rows)] } ?? []
        salva(PDFAnalysisResult(fileName: file.lastPathComponent, date: date, rows: rows, days: days))
    }

    private func salva(_ result: PDFAnalysisResult) {
        analyses.removeAll { $0.fileName == result.fileName }
        analyses.insert(result, at: 0)
        if let data = try? JSONEncoder().encode(analyses) { UserDefaults.standard.set(data, forKey: key) }
    }

    func giorniAzienda() -> [PDFAnalysisDay] {
        var result: [PDFAnalysisDay] = []
        for analysis in analyses {
            if !analysis.days.isEmpty {
                result.append(contentsOf: analysis.days)
            } else if let date = analysis.date {
                result.append(PDFAnalysisDay(date: date, rows: analysis.rows))
            }
        }
        return result
    }

    private func estraiData(_ text: String) -> Date? {
        let pattern = #"\b(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let ns = text as NSString
        let d = Int(ns.substring(with: match.range(at: 1))) ?? 0
        let m = Int(ns.substring(with: match.range(at: 2))) ?? 0
        var y = Int(ns.substring(with: match.range(at: 3))) ?? 0
        if y < 100 { y += 2000 }
        var c = DateComponents(); c.day = d; c.month = m; c.year = y
        return Calendar.current.date(from: c)
    }

    private func estraiRighe(_ text: String) -> [PDFAnalysisRow] {
        var result: [PDFAnalysisRow] = []
        let lines = text.components(separatedBy: .newlines)
        let pattern = #"^\s*(.+?)\s+([0-9]+)\s+(?:([0-9]+(?:[.,][0-9]+)?)\s+)?([0-9]+(?:[.,][0-9]+)?)\s*$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        for line in lines {
            let clean = line.trimmingCharacters(in: .whitespaces)
            guard clean.count >= 3, let regex = regex else { continue }
            let ns = clean as NSString
            guard let m = regex.firstMatch(in: clean, range: NSRange(location: 0, length: ns.length)) else { continue }
            let article = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let quantity = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let unit = m.range(at: 3).location != NSNotFound ? Double(ns.substring(with: m.range(at: 3)).replacingOccurrences(of: ",", with: ".")) : nil
            let total = Double(ns.substring(with: m.range(at: 4)).replacingOccurrences(of: ",", with: "."))
            if quantity > 0 && article.count <= 80 && !article.lowercased().contains("totale") {
                result.append(PDFAnalysisRow(article: article, quantity: quantity, unitPrice: unit, total: total))
            }
        }
        return result
    }
}
