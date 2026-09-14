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

struct PDFAnalysisResult: Identifiable, Codable {
    let id: UUID
    var fileName: String
    var date: Date?
    var rows: [PDFAnalysisRow]
    var analyzedAt: Date

    init(id: UUID = UUID(), fileName: String, date: Date?, rows: [PDFAnalysisRow], analyzedAt: Date = Date()) {
        self.id = id
        self.fileName = fileName
        self.date = date
        self.rows = rows
        self.analyzedAt = analyzedAt
    }
}

final class PDFAnalysisStore: ObservableObject {
    @Published private(set) var results: [PDFAnalysisResult] = []
    private let key = "contabilita_pdf_analysis_results"

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode([PDFAnalysisResult].self, from: data) else { return }
        results = value
    }

    func save(_ result: PDFAnalysisResult) {
        if let index = results.firstIndex(where: { $0.fileName == result.fileName }) {
            results[index] = result
        } else {
            results.insert(result, at: 0)
        }
        if let data = try? JSONEncoder().encode(results) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum PDFAnalyzer {
    static func analyze(url: URL) -> PDFAnalysisResult? {
        guard let document = PDFDocument(url: url) else { return nil }
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let date = findDate(in: text)
        var rows: [PDFAnalysisRow] = []
        let lines = text.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let numbers = numbers(in: line), !numbers.isEmpty else { continue }
            guard let quantity = numbers.last(where: { $0.rounded() == $0 && $0 >= 0 && $0 <= 100000 }) else { continue }
            guard quantity > 0 || numbers.count >= 2 else { continue }

            let article = articlePart(from: line, numbers: numbers)
            guard article.count >= 2 else { continue }
            let upper = article.uppercased()
            let ignored = ["TOTALE", "TOTALI", "PREZZO", "QUANTITA", "QUANTITÀ", "IMPORTO", "DATA", "ARTICOLO"]
            guard !ignored.contains(where: { upper == $0 || upper.hasPrefix($0 + " ") }) else { continue }

            let reversed = numbers.reversed().map { $0 }
            var prezzo: Double?
            var totale: Double?
            if reversed.count >= 3 {
                totale = reversed[0]
                prezzo = reversed[1]
            } else if reversed.count == 2 {
                totale = reversed[0]
                prezzo = reversed[1]
            }
            rows.append(PDFAnalysisRow(articolo: article, quantita: Int(quantity), prezzoUnitario: prezzo, totale: totale))
        }

        // Evita righe duplicate generate da PDF con testo ripetuto nell'intestazione.
        var unique: [String: PDFAnalysisRow] = [:]
        for row in rows {
            let key = normalize(row.articolo)
            if key.isEmpty { continue }
            unique[key] = row
        }
        rows = Array(unique.values).sorted { $0.articolo.localizedCaseInsensitiveCompare($1.articolo) == .orderedAscending }

        guard !rows.isEmpty else { return nil }
        return PDFAnalysisResult(fileName: url.lastPathComponent, date: date, rows: rows)
    }

    private static func numbers(in line: String) -> [Double]? {
        let pattern = #"(?<![A-Za-z])\d{1,7}(?:[\.,]\d{1,2})?(?![A-Za-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        let values = matches.compactMap { match -> Double? in
            let value = ns.substring(with: match.range).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            return Double(value)
        }
        return values.isEmpty ? nil : values
    }

    private static func articlePart(from line: String, numbers: [Double]) -> String {
        let pattern = #"\s+\d{1,7}(?:[\.,]\d{1,2})?\s*$"#
        var result = line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        // Rimuove fino a due numeri finali (prezzo/totale), lasciando il nome dell'articolo.
        for _ in 0..<2 {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func findDate(in text: String) -> Date? {
        let pattern = #"\b(\d{1,2})[\./-](\d{1,2})[\./-](\d{2,4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let ns = text as NSString
        guard let d = Int(ns.substring(with: match.range(at: 1))),
              let m = Int(ns.substring(with: match.range(at: 2))),
              var y = Int(ns.substring(with: match.range(at: 3))) else { return nil }
        if y < 100 { y += 2000 }
        var c = DateComponents(); c.day = d; c.month = m; c.year = y
        return Calendar.current.date(from: c)
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}

struct PDFAnalysisDetailView: View {
    let result: PDFAnalysisResult
    @ObservedObject var archivio: Archivio
    @Environment(\.presentationMode) private var presentationMode

    private var matchingBolletta: Bolletta? {
        guard let date = result.date else { return nil }
        return archivio.bollette.first { Calendar.current.isDate($0.data, inSameDayAs: date) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PDF ANALIZZATO").font(.caption).foregroundColor(.secondary)
                        Text(result.fileName).font(.headline).lineLimit(2)
                    }
                    Spacer()
                    Text(result.date?.formatted(date: .numeric, time: .omitted) ?? "Data non trovata")
                        .foregroundColor(.blue)
                }
                .padding(16)

                if matchingBolletta == nil {
                    Text("Nessuna bolletta caricata da te con la stessa data.")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding()
                }

                List(result.rows) { row in
                    let mine = matchingBolletta?.lavorazioni.first(where: { PDFAnalyzer.normalize($0.nome) == PDFAnalyzer.normalize(row.articolo) })
                    let mineQty = Int(mine?.quantita ?? "") ?? 0
                    let diff = row.quantita - mineQty
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.articolo).font(.headline)
                            if let price = row.prezzoUnitario {
                                Text(String(format: "€ %.2f cad.  •  Totale € %.2f", price, row.totale ?? price * Double(row.quantita)))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Tu: \(mineQty)")
                            Text("Azienda: \(row.quantita)")
                            Text(diff == 0 ? "✓ UGUALE" : "Differenza: \(diff > 0 ? "+" : "")\(diff)")
                                .foregroundColor(diff == 0 ? .green : .red)
                                .fontWeight(.bold)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Analisi e confronto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
