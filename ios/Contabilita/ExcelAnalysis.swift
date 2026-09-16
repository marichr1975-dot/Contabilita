import Foundation
import ZIPFoundation

struct ExcelAnalysisDay {
    let date: Date
    let rows: [PDFAnalysisRow]
}

final class ExcelAnalysis {
    static func analizza(file: URL) -> [ExcelAnalysisDay]? {
        guard let archive = try? Archive(url: file, accessMode: .read),
              let sheetData = leggiFile(archive: archive, path: "xl/worksheets/sheet1.xml") else { return nil }

        let sharedStrings = leggiSharedStrings(archive: archive)
        let righe = estraiRigheXML(sheetData, sharedStrings: sharedStrings)
        guard !righe.isEmpty else { return nil }

        let normalizza: (String) -> String = { testo in
            testo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
        }

        var header = righe[0].map(normalizza)
        var start = 1
        if !header.contains(where: { $0.contains("data") }) ||
           !header.contains(where: { $0.contains("articolo") || $0.contains("modello") || $0.contains("descrizione") || $0.contains("lavorazione") }) {
            if righe.count > 1 {
                header = righe[1].map(normalizza)
                start = 2
            }
        }

        let dataIndex = header.firstIndex(where: { $0.contains("data") })
        let articoloIndex = header.firstIndex(where: { $0.contains("articolo") || $0.contains("modello") || $0.contains("descrizione") || $0.contains("lavorazione") })
        let quantitaIndex = header.firstIndex(where: { $0.contains("quantita") || $0 == "qta" || $0.contains("pezzi") })
        guard let di = dataIndex, let ai = articoloIndex, let qi = quantitaIndex else { return nil }

        var gruppi: [Date: [PDFAnalysisRow]] = [:]
        for riga in righe.dropFirst(start) {
            guard di < riga.count, ai < riga.count, qi < riga.count,
                  let data = dataDaValore(riga[di]) else { continue }
            let articolo = riga[ai].trimmingCharacters(in: .whitespacesAndNewlines)
            let quantita = Int(riga[qi]) ?? Int(Double(riga[qi].replacingOccurrences(of: ",", with: ".")) ?? -1)
            guard !articolo.isEmpty, quantita >= 0 else { continue }
            gruppi[data, default: []].append(PDFAnalysisRow(article: articolo, quantity: quantita))
        }

        return gruppi.keys.sorted().map { ExcelAnalysisDay(date: $0, rows: gruppi[$0] ?? []) }
    }

    private static func leggiSharedStrings(archive: Archive) -> [String] {
        guard let data = leggiFile(archive: archive, path: "xl/sharedStrings.xml"),
              let xml = String(data: data, encoding: .utf8) else { return [] }
        let regex = try? NSRegularExpression(pattern: #"<t[^>]*>(.*?)</t>"#, options: [.dotMatchesLineSeparators])
        guard let regex = regex else { return [] }
        let ns = xml as NSString
        return regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)).map {
            decodeXML(ns.substring(with: $0.range(at: 1)))
        }
    }

    private static func leggiFile(archive: Archive, path: String) -> Data? {
        guard let entry = archive[path] else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in data.append(chunk) }
            return data
        } catch { return nil }
    }

    private static func estraiRigheXML(_ data: Data, sharedStrings: [String]) -> [[String]] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        let rowRegex = try? NSRegularExpression(pattern: #"<row\b[^>]*>(.*?)</row>"#, options: [.dotMatchesLineSeparators])
        let cellRegex = try? NSRegularExpression(pattern: #"<c\b([^>]*)>(.*?)</c>"#, options: [.dotMatchesLineSeparators])
        guard let rowRegex, let cellRegex else { return [] }
        let ns = xml as NSString
        var rows: [[String]] = []

        for rowMatch in rowRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let rowXML = ns.substring(with: rowMatch.range(at: 1))
            let rowNS = rowXML as NSString
            var cells: [(Int, String)] = []
            for cellMatch in cellRegex.matches(in: rowXML, range: NSRange(location: 0, length: rowNS.length)) {
                let attrs = rowNS.substring(with: cellMatch.range(at: 1))
                let body = rowNS.substring(with: cellMatch.range(at: 2))
                let ref = valoreAttributo(attrs, nome: "r") ?? "A1"
                let type = valoreAttributo(attrs, nome: "t")
                var testo = valoreTag(body, tag: "v") ?? ""
                if type == "s", let idx = Int(testo), idx >= 0, idx < sharedStrings.count { testo = sharedStrings[idx] }
                if type == "inlineStr" { testo = valoreTag(body, tag: "t") ?? testo }
                cells.append((columnIndex(String(ref.prefix { $0.isLetter })), decodeXML(testo)))
            }
            guard let max = cells.map({ $0.0 }).max() else { continue }
            var row = Array(repeating: "", count: max + 1)
            for (index, value) in cells { row[index] = value }
            rows.append(row)
        }
        return rows
    }

    private static func valoreAttributo(_ testo: String, nome: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: nome)
        let regex = try? NSRegularExpression(pattern: #"\b"# + escaped + #"=\"([^\"]+)\""#)
        guard let regex, let match = regex.firstMatch(in: testo, range: NSRange(location: 0, length: (testo as NSString).length)) else { return nil }
        return (testo as NSString).substring(with: match.range(at: 1))
    }

    private static func valoreTag(_ testo: String, tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        let regex = try? NSRegularExpression(pattern: #"<"# + escaped + #"[^>]*>(.*?)</"# + escaped + #">"#, options: [.dotMatchesLineSeparators])
        guard let regex, let match = regex.firstMatch(in: testo, range: NSRange(location: 0, length: (testo as NSString).length)) else { return nil }
        return (testo as NSString).substring(with: match.range(at: 1))
    }

    private static func columnIndex(_ letters: String) -> Int {
        var value = 0
        for scalar in letters.unicodeScalars { value = value * 26 + Int(scalar.value - 64) }
        return max(0, value - 1)
    }

    private static func dataDaValore(_ valore: String) -> Date? {
        let s = valore.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$"#
        if let re = try? NSRegularExpression(pattern: pattern),
           let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
            let ns = s as NSString
            let d = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let mo = Int(ns.substring(with: m.range(at: 2))) ?? 0
            var y = Int(ns.substring(with: m.range(at: 3))) ?? 0
            if y < 100 { y += 2000 }
            guard (1...31).contains(d), (1...12).contains(mo), (2000...2100).contains(y) else { return nil }
            var c = DateComponents()
            c.day = d; c.month = mo; c.year = y
            return Calendar(identifier: .gregorian).date(from: c)
        }

        // Excel serial date (1900 date system). Accept only a realistic range,
        // so quantities or other numbers can never become absurd dates.
        if let serial = Double(s), serial >= 30000, serial <= 60000 {
            var base = DateComponents()
            base.year = 1899; base.month = 12; base.day = 30
            let calendar = Calendar(identifier: .gregorian)
            guard let epoch = calendar.date(from: base) else { return nil }
            return calendar.date(byAdding: .day, value: Int(serial.rounded()), to: epoch)
        }
        return nil
    }

    private static func decodeXML(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
