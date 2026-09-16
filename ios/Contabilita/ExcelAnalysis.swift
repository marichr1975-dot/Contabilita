import Foundation
import ZIPFoundation

struct ExcelAnalysisDay {
    let date: Date
    let rows: [PDFAnalysisRow]
}

final class ExcelAnalysis {

    static func analizza(file: URL) -> [ExcelAnalysisDay]? {
        guard file.pathExtension.lowercased() == "xlsx" else { return nil }

        let archive: Archive
        do {
            archive = try Archive(url: file, accessMode: .read)
        } catch {
            return nil
        }

        let sharedStrings = leggiSharedStrings(archive: archive)

        let fogli = archive
            .filter { $0.path.hasPrefix("xl/worksheets/") && $0.path.hasSuffix(".xml") }
            .map(\.path)
            .sorted()

        for foglio in fogli {
            guard let data = leggiFile(archive: archive, path: foglio) else { continue }
            let righe = estraiRigheXML(data, sharedStrings: sharedStrings)
            if let result = analizzaFoglio(righe), !result.isEmpty {
                return result
            }
        }

        return nil
    }

    private static func analizzaFoglio(_ righe: [[String]]) -> [ExcelAnalysisDay]? {
        guard !righe.isEmpty else { return nil }

        func normalizza(_ testo: String) -> String {
            testo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ".", with: "")
        }

        // Formato del prospetto aziendale:
        // riga precedente = prezzi unitari
        // riga intestazioni = DATA + nomi articoli
        // righe successive = data + quantità per articolo
        var headerIndex: Int?
        var dataIndex = -1
        var articleColumns: [(Int, String)] = []

        for (i, row) in righe.enumerated() {
            guard let di = row.firstIndex(where: {
                let n = normalizza($0)
                return n == "data" || n.contains("data")
            }) else { continue }

            var articles: [(Int, String)] = []
            for (j, value) in row.enumerated() where j != di {
                let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                let n = normalizza(name)
                guard !name.isEmpty else { continue }
                guard !n.contains("prezzounitario"),
                      !n.contains("totalepezzi"),
                      !n.contains("totaleeuro"),
                      !n.contains("totalegenerale") else { continue }
                articles.append((j, name))
            }

            guard articles.count >= 1 else { continue }

            headerIndex = i
            dataIndex = di
            articleColumns = articles
            break
        }

        guard let hi = headerIndex, dataIndex >= 0 else { return nil }

        var prices: [Int: Double] = [:]
        if hi > 0 {
            let priceRow = righe[hi - 1]
            for (column, _) in articleColumns where column < priceRow.count {
                if let value = numero(priceRow[column]) {
                    prices[column] = value
                }
            }
        }

        var days: [Date: [PDFAnalysisRow]] = [:]

        for row in righe.dropFirst(hi + 1) {
            guard dataIndex < row.count,
                  let date = data(row[dataIndex]) else { continue }

            var values: [PDFAnalysisRow] = []

            for (column, article) in articleColumns where column < row.count {
                guard let q = numero(row[column]), q > 0 else { continue }

                let quantity = Int(q.rounded())
                guard quantity > 0 else { continue }

                let unit = prices[column]
                let total = unit.map { Double(quantity) * $0 }

                values.append(
                    PDFAnalysisRow(
                        article: article,
                        quantity: quantity,
                        unitPrice: unit,
                        total: total
                    )
                )
            }

            if !values.isEmpty {
                days[Calendar.current.startOfDay(for: date), default: []].append(contentsOf: values)
            }
        }

        guard !days.isEmpty else { return nil }

        return days.keys.sorted().map {
            ExcelAnalysisDay(date: $0, rows: days[$0] ?? [])
        }
    }

    private static func numero(_ value: String) -> Double? {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard !s.isEmpty else { return nil }
        if let n = Double(s) { return n }

        return Double(
            s.replacingOccurrences(of: ".", with: "")
             .replacingOccurrences(of: ",", with: ".")
        )
    }

    private static func data(_ value: String) -> Date? {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)

        let formats = ["dd/MM/yyyy", "dd-MM-yyyy", "dd.MM.yyyy", "d/M/yyyy", "d-M-yyyy", "d.M.yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.calendar = Calendar(identifier: .gregorian)

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: s) { return date }
        }

        if let serial = Double(s), serial >= 30000, serial <= 60000 {
            var components = DateComponents()
            components.year = 1899
            components.month = 12
            components.day = 30
            guard let epoch = Calendar(identifier: .gregorian).date(from: components) else {
                return nil
            }
            return Calendar(identifier: .gregorian).date(byAdding: .day, value: Int(serial.rounded()), to: epoch)
        }

        return nil
    }

    private static func leggiSharedStrings(archive: Archive) -> [String] {
        guard let data = leggiFile(archive: archive, path: "xl/sharedStrings.xml"),
              let xml = String(data: data, encoding: .utf8) else { return [] }

        let siRegex = try? NSRegularExpression(
            pattern: #"<si\b[^>]*>(.*?)</si>"#,
            options: [.dotMatchesLineSeparators]
        )
        let tRegex = try? NSRegularExpression(
            pattern: #"<t\b[^>]*>(.*?)</t>"#,
            options: [.dotMatchesLineSeparators]
        )
        guard let siRegex, let tRegex else { return [] }

        let ns = xml as NSString
        var result: [String] = []

        for match in siRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let body = ns.substring(with: match.range(at: 1))
            let bodyNS = body as NSString
            var text = ""

            for tm in tRegex.matches(in: body, range: NSRange(location: 0, length: bodyNS.length)) {
                text += decodeXML(bodyNS.substring(with: tm.range(at: 1)))
            }

            result.append(text)
        }

        return result
    }

    private static func leggiFile(archive: Archive, path: String) -> Data? {
        guard let entry = archive[path] else { return nil }
        var data = Data()

        do {
            try archive.extract(entry) { chunk in
                data.append(chunk)
            }
            return data
        } catch {
            return nil
        }
    }

    private static func estraiRigheXML(_ data: Data, sharedStrings: [String]) -> [[String]] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }

        let rowRegex = try? NSRegularExpression(
            pattern: #"<row\b[^>]*>(.*?)</row>"#,
            options: [.dotMatchesLineSeparators]
        )
        let cellRegex = try? NSRegularExpression(
            pattern: #"<c\b([^>]*)>(.*?)</c>"#,
            options: [.dotMatchesLineSeparators]
        )
        guard let rowRegex, let cellRegex else { return [] }

        let ns = xml as NSString
        var rows: [[String]] = []

        for rm in rowRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let rowXML = ns.substring(with: rm.range(at: 1))
            let rowNS = rowXML as NSString
            var cells: [(Int, String)] = []

            for cm in cellRegex.matches(in: rowXML, range: NSRange(location: 0, length: rowNS.length)) {
                let attrs = rowNS.substring(with: cm.range(at: 1))
                let body = rowNS.substring(with: cm.range(at: 2))
                let ref = attribute(attrs, "r") ?? "A1"
                let type = attribute(attrs, "t")
                var value = tag(body, "v") ?? ""

                if type == "s", let index = Int(value), index >= 0, index < sharedStrings.count {
                    value = sharedStrings[index]
                } else if type == "inlineStr" {
                    value = tag(body, "t") ?? value
                }

                let letters = String(ref.prefix { $0.isLetter })
                cells.append((columnIndex(letters), decodeXML(value)))
            }

            guard let max = cells.map(\.0).max() else { continue }
            var row = Array(repeating: "", count: max + 1)
            for (index, value) in cells { row[index] = value }
            rows.append(row)
        }

        return rows
    }

    private static func attribute(_ text: String, _ name: String) -> String? {
        let regex = try? NSRegularExpression(
            pattern: #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"="([^"]+)""#
        )
        guard let regex,
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (text as NSString).substring(with: m.range(at: 1))
    }

    private static func tag(_ text: String, _ name: String) -> String? {
        let n = NSRegularExpression.escapedPattern(for: name)
        let regex = try? NSRegularExpression(
            pattern: #"<"# + n + #"[^>]*>(.*?)</"# + n + #">"#,
            options: [.dotMatchesLineSeparators]
        )
        guard let regex,
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (text as NSString).substring(with: m.range(at: 1))
    }

    private static func columnIndex(_ letters: String) -> Int {
        var value = 0
        for scalar in letters.uppercased().unicodeScalars where scalar.value >= 65 && scalar.value <= 90 {
            value = value * 26 + Int(scalar.value - 64)
        }
        return max(0, value - 1)
    }

    private static func decodeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
