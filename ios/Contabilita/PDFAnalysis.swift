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

    private enum CodingKeys: String, CodingKey {
        case id, fileName, date, rows, days
    }

    init(id: UUID = UUID(), fileName: String, date: Date?, rows: [PDFAnalysisRow], days: [PDFAnalysisDay] = []) {
        self.id = id
        self.fileName = fileName
        self.date = date
        self.rows = rows
        self.days = days
    }

    // Compatibilità con le analisi salvate nelle versioni precedenti:
    // il campo days non esisteva, quindi deve essere facoltativo in lettura.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        rows = try container.decodeIfPresent([PDFAnalysisRow].self, forKey: .rows) ?? []
        days = try container.decodeIfPresent([PDFAnalysisDay].self, forKey: .days) ?? []
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
            salva(PDFAnalysisResult(
                fileName: file.lastPathComponent,
                date: days.first?.date,
                rows: days.flatMap { $0.rows },
                days: days
            ))
            return
        }

        guard let document = PDFDocument(url: file) else { return }
        let days = estraiGiorniPDF(document)
        let first = days.first
        salva(PDFAnalysisResult(
            fileName: file.lastPathComponent,
            date: first?.date,
            rows: days.flatMap { $0.rows },
            days: days
        ))
    }

    private func salva(_ result: PDFAnalysisResult) {
        analyses.removeAll { $0.fileName == result.fileName }
        analyses.insert(result, at: 0)
        if let data = try? JSONEncoder().encode(analyses) {
            UserDefaults.standard.set(data, forKey: key)
        }
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

    // The BAGFUL PDF is a table: one date per row and the quantities are
    // positioned under fixed article columns. PDFKit's plain text extraction
    // loses empty cells, so here we keep the character coordinates and rebuild
    // the table from the X/Y positions.
    private struct Word {
        let text: String
        let rect: CGRect
    }

    private func estraiGiorniPDF(_ document: PDFDocument) -> [PDFAnalysisDay] {
        let articoli = [
            "MESSENGER", "BAGPACK", "TODAY", "ACTIVITY", "ZAINI MARIN",
            "CLASSY", "ZAINO PRO", "case marina", "MONEYFUL", "BORSA IN STOFFA", "PORTAPC"
        ]

        // Centri reali delle 10 colonne del prospetto BAGFUL.
        // PORTAPC è la colonna più a destra (circa X=686), non X=635.
        let columnCenters: [CGFloat] = [148, 199, 249, 300, 351, 402, 453, 503, 554, 686]
        let dateRegex = try! NSRegularExpression(
            pattern: #"(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})"#
        )

        var trovati: [PDFAnalysisDay] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let text = page.string, !text.isEmpty else { continue }

            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            let dateMatches = dateRegex.matches(in: text, range: fullRange)
            let words = paroleConPosizione(page)

            for match in dateMatches {
                let rawDate = nsText.substring(with: match.range)
                guard let date = dataDaStringa(rawDate) else { continue }

                // Ricaviamo direttamente la posizione della DATA dai suoi
                // caratteri. Non dipendiamo più da words.first(where: ...):
                // anche se PDFKit divide la parola in modo diverso, la data
                // rimane riconosciuta e la sua riga viene individuata.
                var dateRect = CGRect.null
                let start = match.range.location
                let end = start + match.range.length
                if start < end {
                    for index in start..<end {
                        let r = page.characterBounds(at: index)
                        if !r.isNull && !r.isEmpty { dateRect = dateRect.union(r) }
                    }
                }

                // Fallback: cerca una parola che contenga la data.
                if dateRect.isNull || dateRect.isEmpty {
                    if let dateWord = words.first(where: { $0.text == rawDate }) {
                        dateRect = dateWord.rect
                    }
                }

                var rows: [PDFAnalysisRow] = []
                if !dateRect.isNull && !dateRect.isEmpty {
                    let rowY = dateRect.midY
                    let numericWords = words.filter { word in
                        guard abs(word.rect.midY - rowY) <= 3.5 else { return false }
                        guard word.rect.minX > 125 else { return false }
                        guard word.rect.maxX < 705 else { return false }
                        return Int(word.text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
                    }

                    for index in 0..<articoli.count {
                        let center = columnCenters[index]
                        // Una cella vuota non produce alcuna parola nel PDF.
                        // Cerchiamo quindi solo un numero realmente vicino
                        // alla colonna corrente.
                        guard let token = numericWords.min(by: {
                            abs($0.rect.midX - center) < abs($1.rect.midX - center)
                        }) else { continue }
                        guard abs(token.rect.midX - center) <= 12,
                              let quantity = Int(token.text), quantity > 0 else { continue }
                        rows.append(PDFAnalysisRow(article: articoli[index], quantity: quantity))
                    }
                }

                trovati.append(PDFAnalysisDay(date: date, rows: rows))
            }
        }

        // Una sola voce per ogni giorno, ordinate dalla più recente alla più vecchia.
        var perData: [Date: [PDFAnalysisRow]] = [:]
        let calendario = Calendar(identifier: .gregorian)
        for day in trovati {
            let key = calendario.startOfDay(for: day.date)
            perData[key, default: []].append(contentsOf: day.rows)
        }

        return perData.keys.sorted(by: >).map { date in
            var aggregate: [String: PDFAnalysisRow] = [:]
            for row in perData[date] ?? [] {
                if let existing = aggregate[row.article] {
                    aggregate[row.article] = PDFAnalysisRow(
                        article: existing.article,
                        quantity: existing.quantity + row.quantity
                    )
                } else {
                    aggregate[row.article] = row
                }
            }
            return PDFAnalysisDay(
                date: date,
                rows: aggregate.values.sorted { $0.article < $1.article }
            )
        }
    }

    private func paroleConPosizione(_ page: PDFPage) -> [Word] {
        guard let text = page.string, !text.isEmpty else { return [] }

        let nsText = text as NSString
        let pattern = #"\S+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var result: [Word] = []
        result.reserveCapacity(matches.count)

        for match in matches {
            let range = match.range
            let word = nsText.substring(with: range)
            guard !word.isEmpty else { continue }

            var rect = CGRect.null
            var found = false
            let start = range.location
            let end = range.location + range.length

            if start < end {
                for index in start..<end {
                    let charRect = page.characterBounds(at: index)
                    if !charRect.isNull && !charRect.isEmpty {
                        rect = rect.union(charRect)
                        found = true
                    }
                }
            }

            if found {
                result.append(Word(text: word, rect: rect))
            }
        }

        return result
    }

    private func centriColonne(_ numericWords: [Word]) -> [CGFloat] {
        let xs = numericWords.map { $0.rect.midX }.sorted()
        guard !xs.isEmpty else { return [] }

        // Cluster recurring X positions. The supplied BAGFUL file has 10
        // article columns; if fewer are actually used, fewer centers are kept.
        var centers: [CGFloat] = []
        for x in xs {
            if let last = centers.last, abs(last - x) < 12 {
                centers[centers.count - 1] = (last + x) / 2
            } else {
                centers.append(x)
            }
        }
        return centers.sorted()
    }

    private func dataDaStringa(_ valore: String) -> Date? {
        let s = valore.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }

        let ns = s as NSString
        let day = Int(ns.substring(with: match.range(at: 1))) ?? 0
        let month = Int(ns.substring(with: match.range(at: 2))) ?? 0
        var year = Int(ns.substring(with: match.range(at: 3))) ?? 0
        if year < 100 { year += 2000 }

        guard (1...31).contains(day),
              (1...12).contains(month),
              (2000...2100).contains(year) else { return nil }

        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        return Calendar(identifier: .gregorian).date(from: components)
    }
}
