import Foundation
import PDFKit
import SwiftUI

struct PDFAnalysisRow: Identifiable, Codable {
    let id: UUID
    var articolo: String
    var quantita: Int
    var prezzoUnitario: Double?
    var totale: Double?

    init(id: UUID = UUID(), articolo: String, quantita: Int, prezzoUnitario: Double? = nil, totale: Double? = nil) {
        self.id = id
        self.articolo = articolo
        self.quantita = quantita
        self.prezzoUnitario = prezzoUnitario
        self.totale = totale
    }
}

struct PDFAnalysis: Identifiable, Codable {
    let id: UUID
    var fileName: String
    var dataBolletta: Date?
    var rows: [PDFAnalysisRow]
    var rawText: String
    var analyzedAt: Date

    init(id: UUID = UUID(), fileName: String, dataBolletta: Date? = nil, rows: [PDFAnalysisRow], rawText: String, analyzedAt: Date = Date()) {
        self.id = id
        self.fileName = fileName
        self.dataBolletta = dataBolletta
        self.rows = rows
        self.rawText = rawText
        self.analyzedAt = analyzedAt
    }
}

final class PDFAnalysisStore: ObservableObject {
    @Published private(set) var analyses: [PDFAnalysis] = []
    private let key = "contabilita_pdf_analyses"

    init() { carica() }

    func carica() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode([PDFAnalysis].self, from: data) else { return }
        analyses = value
    }

    func analisiPerFile(_ url: URL) -> PDFAnalysis? {
        analyses.first { $0.fileName == url.lastPathComponent }
    }

    @discardableResult
    func analizza(_ url: URL) -> PDFAnalysis? {
        guard let document = PDFDocument(url: url) else { return nil }
        var text = ""
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let date = Self.extractDate(from: text)
        let rows = Self.extractRows(from: text)
        let result = PDFAnalysis(fileName: url.lastPathComponent, dataBolletta: date, rows: rows, rawText: text)
        analyses.removeAll { $0.fileName == result.fileName }
        analyses.insert(result, at: 0)
        if let data = try? JSONEncoder().encode(analyses) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return result
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func extractDate(from text: String) -> Date? {
        let patterns = [
            #"\b(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})\b"#,
            #"\b(\d{4})[./-](\d{1,2})[./-](\d{1,2})\b"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let values = (1...3).compactMap { i -> Int? in
                    guard let r = Range(match.range(at: i), in: text) else { return nil }
                    return Int(text[r])
                }
                if values.count == 3 {
                    let d: Int, m: Int, y: Int
                    if values[0] > 31 { y = values[0]; m = values[1]; d = values[2] }
                    else { d = values[0]; m = values[1]; y = values[2] < 100 ? 2000 + values[2] : values[2] }
                    var comps = DateComponents(); comps.day = d; comps.month = m; comps.year = y
                    if let date = Calendar.current.date(from: comps) { return date }
                }
            }
        }
        return nil
    }

    private static func number(_ value: String) -> Double? {
        var s = value.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "EUR", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains(",") && s.contains(".") { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        else { s = s.replacingOccurrences(of: ",", with: ".") }
        return Double(s)
    }

    private static func extractRows(from text: String) -> [PDFAnalysisRow] {
        var result: [PDFAnalysisRow] = []
        let lines = normalizedLines(text)
        let skip = ["totale", "data", "articolo", "quantità", "quantita", "prezzo", "unitario", "prospetto", "azienda"]

        for line in lines {
            let upper = line.uppercased()
            if skip.contains(where: { upper == $0 || upper.hasPrefix($0 + " ") }) { continue }
            let tokens = line.components(separatedBy: " ")
            guard tokens.count >= 2 else { continue }

            let numeric = tokens.enumerated().compactMap { idx, token -> (Int, Double)? in
                guard let value = number(token) else { return nil }
                return (idx, value)
            }
            guard let first = numeric.first else { continue }

            // The first integer-looking value is treated as quantity; trailing monetary values are price/total.
            let quantityIndex = first.0
            let quantity = Int(first.1.rounded())
            guard quantity >= 0, quantityIndex < tokens.count - 1 else { continue }

            let article = tokens[0...quantityIndex-1].joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !article.isEmpty, article.count >= 2 else { continue }
            let money = numeric.dropFirst().map { $0.1 }
            let price = money.first
            let total = money.count > 1 ? money.last : nil
            result.append(PDFAnalysisRow(articolo: article, quantita: quantity, prezzoUnitario: price, totale: total))
        }
        return result
    }
}

struct PDFAnalysisDetailView: View {
    let analysis: PDFAnalysis
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            List {
                if let date = analysis.dataBolletta {
                    HStack { Text("Data"); Spacer(); Text(date.formatted(date: .numeric, time: .omitted)).fontWeight(.semibold) }
                }
                Section("RIGHE RICONOSCIUTE") {
                    if analysis.rows.isEmpty {
                        Text("Nessuna riga riconosciuta automaticamente. Il PDF è stato letto ma il formato non consente di identificare con certezza le colonne.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(analysis.rows) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.articolo).font(.headline)
                                HStack {
                                    Text("Quantità: \(row.quantita)")
                                    Spacer()
                                    if let p = row.prezzoUnitario { Text(String(format: "€ %.2f", p)) }
                                    if let t = row.totale { Text(String(format: "€ %.2f", t)) }
                                }.font(.subheadline).foregroundColor(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                }
                Section("TESTO LETTO DAL PDF") {
                    Text(analysis.rawText).font(.footnote).textSelection(.enabled)
                }
            }
            .navigationTitle("Dati analizzati")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Chiudi") { presentationMode.wrappedValue.dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }
}
