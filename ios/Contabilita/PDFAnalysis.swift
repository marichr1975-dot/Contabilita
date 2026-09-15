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
        // Il prospetto BAGFUL è una tabella: una data per riga e le quantità
        // nelle colonne degli articoli. La data viene individuata direttamente
        // sui caratteri PDF, così nessuna riga viene persa se PDFKit spezza o
        // fonde una parola durante l'estrazione.
        let articoli = [
            "MESSENGER BAGPACK", "TODAY", "ACTIVITY", "ZAINI MARIN", "CLASSY",
            "ZAINO PRO", "CASE MARINA", "MONEYFUL", "BORSA IN STOFFA", "PORTAPC"
        ]

        // Bordi destri delle colonne del prospetto reale fornito.
        let rightEdges: [CGFloat] = [151, 202, 253, 304, 355, 406, 457, 558, 639, 690]
        let dateRegex = try? NSRegularExpression(
            pattern: #"(?<!\d)(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})(?!\d)"#
        )

        var trovati: [PDFAnalysisDay] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let pageText = page.string else { continue }

            let nsText = pageText as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            let matches = dateRegex?.matches(in: pageText, range: fullRange) ?? []
            let words = paroleConPosizione(page)

            for match in matches {
                let raw = nsText.substring(with: match.range)
                guard let date = dataDaStringa(raw) else { continue }

                // Ricaviamo la posizione della data dai caratteri originali.
                var dateRect = CGRect.null
                for i in match.range.location..<(match.range.location + match.range.length) {
                    let r = page.characterBounds(at: i)
                    if !r.isNull { dateRect = dateRect.isNull ? r : dateRect.union(r) }
                }

                var rows: [PDFAnalysisRow] = []
                if !dateRect.isNull {
                    let rowY = dateRect.midY
                    let nums = words.compactMap { word -> Word? in
                        guard let value = Int(word.text), value >= 0 else { return nil }
                        guard abs(word.rect.midY - rowY) < 6 else { return nil }
                        return word
                    }

                    // Una cella vuota non produce alcun numero nel PDF. Perciò
                    // scegliamo, per ogni colonna, soltanto un numero realmente
                    // presente entro la tolleranza della colonna.
                    for (index, edge) in rightEdges.enumerated() {
                        guard let token = nums.min(by: {
                            abs($0.rect.maxX - edge) < abs($1.rect.maxX - edge)
                        }) else { continue }
                        guard abs(token.rect.maxX - edge) <= 10,
                              let quantity = Int(token.text), quantity > 0 else { continue }
                        rows.append(PDFAnalysisRow(article: articoli[index], quantity: quantity))
                    }
                }

                // IMPORTANTISSIMO: la giornata viene aggiunta anche se non è
                // stata trovata nessuna quantità. La data non deve mai sparire.
                trovati.append(PDFAnalysisDay(date: date, rows: rows))
            }
        }

        // Se una data compare una sola volta (come nel prospetto fornito), la
        // conserviamo. Se compare più volte, sommiamo le quantità per articolo.
        var perData: [Date: [PDFAnalysisRow]] = [:]
        for day in trovati {
            let key = Calendar(identifier: .gregorian).startOfDay(for: day.date)
            perData[key, default: []].append(contentsOf: day.rows)
        }

        return perData.keys.sorted(by: >).map { date in
            var aggregate: [String: PDFAnalysisRow] = [:]
            for row in perData[date] ?? [] {
                let key = row.article
                if let existing = aggregate[key] {
                    aggregate[key] = PDFAnalysisRow(article: existing.article,
                                                     quantity: existing.quantity + row.quantity)
                } else {
                    aggregate[key] = row
                }
            }
            return PDFAnalysisDay(date: date,
                                  rows: aggregate.values.sorted { $0.article < $1.article })
        }
    }

    private func paroleConPosizione(_ page: PDFPage) -> [Word] {
        guard let string = page.string else { return [] }
        let ns = string as NSString
        var result: [Word] = []
        var current = ""
        var currentRect = CGRect.null
        var previousRect = CGRect.null

        func flush() {
            let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty && !currentRect.isNull {
                result.append(Word(text: text, rect: currentRect))
            }
            current = ""
            currentRect = .null
        }

        for i in 0..<ns.length {
            let character = ns.substring(with: NSRange(location: i, length: 1))
            let rect = page.characterBounds(at: i)
            if rect.isNull { continue }

            let isSpace = character.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
            let sameLine = !previousRect.isNull && abs(rect.midY - previousRect.midY) < 3
            let gap = !previousRect.isNull ? rect.minX - previousRect.maxX : 0

            if isSpace || (!current.isEmpty && (!sameLine || gap > 6)) {
                flush()
            }

            if !isSpace {
                if current.isEmpty {
                    current = character
                    currentRect = rect
                } else {
                    current.append(character)
                    currentRect = currentRect.union(rect)
                }
            }
            previousRect = rect
        }
        flush()
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
