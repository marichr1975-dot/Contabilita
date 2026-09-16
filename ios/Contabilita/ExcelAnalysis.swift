import Foundation
import ZIPFoundation

/// Una giornata di lavorazioni letta direttamente da un file Excel .xlsx.
struct ExcelAnalysisDay {
    let date: Date
    let rows: [PDFAnalysisRow]
}

final class ExcelAnalysis {

    /// Legge file Excel .xlsx senza convertirli in PDF.
    ///
    /// Il formato atteso è quello del prospetto aziendale:
    /// - una riga con i prezzi unitari;
    /// - una riga con le intestazioni DATA + articoli;
    /// - una riga per ogni giornata di lavorazione.
    ///
    /// L'intestazione non deve essere necessariamente alla riga 1:
    /// viene cercata automaticamente.
    static func analizza(file: URL) -> [ExcelAnalysisDay]? {
        guard file.pathExtension.lowercased() == "xlsx" else {
            // Il vecchio formato .xls è binario e non può essere letto
            // semplicemente come ZIP/XML. Per ora accettiamo .xlsx.
            return nil
        }

        guard let archive = try? Archive(url: file, accessMode: .read) else {
            return nil
        }

        let sharedStrings = leggiSharedStrings(archive: archive)

        // Cerca tutti i fogli presenti nel file. In questo modo non dipendiamo
        // dal fatto che il prospetto sia necessariamente "sheet1.xml".
        let worksheetPaths = percorsiFogli(archive: archive)

        guard !worksheetPaths.isEmpty else { return nil }

        var tuttiIGiorni: [ExcelAnalysisDay] = []

        for path in worksheetPaths {
            guard let sheetData = leggiFile(archive: archive, path: path) else {
                continue
            }

            let righe = estraiRigheXML(sheetData, sharedStrings: sharedStrings)
            guard !righe.isEmpty else { continue }

            if let giorni = analizzaFoglio(righe) {
                tuttiIGiorni.append(contentsOf: giorni)
            }
        }

        guard !tuttiIGiorni.isEmpty else { return nil }

        // Se lo stesso giorno compare in più fogli, uniamo le lavorazioni.
        let calendario = Calendar(identifier: .gregorian)
        var perData: [Date: [PDFAnalysisRow]] = [:]

        for giorno in tuttiIGiorni {
            let chiave = calendario.startOfDay(for: giorno.date)
            perData[chiave, default: []].append(contentsOf: giorno.rows)
        }

        return perData.keys.sorted(by: >).map { data in
            var aggregate: [String: PDFAnalysisRow] = [:]

            for row in perData[data] ?? [] {
                if let existing = aggregate[row.article] {
                    let prezzo: Double? = existing.unitPrice ?? row.unitPrice
                    let totale: Double? = prezzo.map {
                        Double(existing.quantity + row.quantity) * $0
                    }

                    aggregate[row.article] = PDFAnalysisRow(
                        article: existing.article,
                        quantity: existing.quantity + row.quantity,
                        unitPrice: prezzo,
                        total: totale
                    )
                } else {
                    aggregate[row.article] = row
                }
            }

            return ExcelAnalysisDay(
                date: data,
                rows: aggregate.values.sorted {
                    $0.article.localizedCaseInsensitiveCompare($1.article) == .orderedAscending
                }
            )
        }
    }

    // MARK: - Lettura del singolo foglio

    private static func analizzaFoglio(_ righe: [[String]]) -> [ExcelAnalysisDay]? {
        let normalizza: (String) -> String = { testo in
            testo
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ".", with: "")
        }

        // Cerca la riga che contiene DATA e almeno due intestazioni articolo.
        // Nel file di test l'intestazione è alla riga 3, ma può trovarsi
        // anche più avanti.
        var headerIndex: Int?
        var dataColumn = -1
        var articleColumns: [(index: Int, name: String)] = []

        for (rowIndex, riga) in righe.enumerated() {
            let intestazioni = riga.map(normalizza)

            guard let di = intestazioni.firstIndex(where: {
                $0 == "data" || $0.contains("data")
            }) else {
                continue
            }

            var articoli: [(Int, String)] = []

            for (index, valore) in riga.enumerated() where index != di {
                let nome = valore.trimmingCharacters(in: .whitespacesAndNewlines)
                let n = normalizza(nome)

                // Ignora colonne vuote e intestazioni chiaramente non articolo.
                guard !nome.isEmpty else { continue }
                guard !n.contains("prezzounitario"),
                      !n.contains("totalepezzi"),
                      !n.contains("totaleeuro"),
                      !n.contains("totalegenerale") else { continue }

                // Sono considerate articoli le colonne con un'intestazione
                // testuale non generica.
                articoli.append((index, nome))
            }

            guard articoli.count >= 2 else { continue }

            headerIndex = rowIndex
            dataColumn = di
            articleColumns = articoli
            break
        }

        guard let hi = headerIndex, dataColumn >= 0, !articleColumns.isEmpty else {
            return nil
        }

        // Nel prospetto aziendale i prezzi sono normalmente nella riga
        // immediatamente precedente all'intestazione.
        let prezziRow = hi > 0 ? righe[hi - 1] : []

        var prezzi: [Int: Double] = [:]
        for col in articleColumns {
            if col.index < prezziRow.count,
               let prezzo = numeroDaStringa(prezziRow[col.index]),
               prezzo >= 0 {
                prezzi[col.index] = prezzo
            }
        }

        var risultati: [ExcelAnalysisDay] = []

        // Tutte le righe successive all'intestazione sono potenziali giornate.
        for riga in righe.dropFirst(hi + 1) {
            guard dataColumn < riga.count,
                  let data = dataDaValore(riga[dataColumn]) else {
                continue
            }

            var rows: [PDFAnalysisRow] = []

            for col in articleColumns {
                guard col.index < riga.count else { continue }

                let testoQuantita = riga[col.index]
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !testoQuantita.isEmpty,
                      let numero = numeroDaStringa(testoQuantita),
                      numero > 0 else {
                    continue
                }

                let quantita = Int(numero.rounded())
                guard quantita > 0 else { continue }

                let prezzo = prezzi[col.index]
                let totale = prezzo.map { Double(quantita) * $0 }

                rows.append(
                    PDFAnalysisRow(
                        article: col.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        quantity: quantita,
                        unitPrice: prezzo,
                        total: totale
                    )
                )
            }

            // Salva solo giornate che hanno almeno una lavorazione.
            if !rows.isEmpty {
                risultati.append(
                    ExcelAnalysisDay(
                        date: data,
                        rows: rows
                    )
                )
            }
        }

        return risultati
    }

    // MARK: - Fogli Excel

    private static func percorsiFogli(archive: Archive) -> [String] {
        // Prima prova i percorsi standard delle worksheet.
        let standard = archive
            .filter { $0.path.hasPrefix("xl/worksheets/") && $0.path.hasSuffix(".xml") }
            .map { $0.path }
            .sorted()

        return standard
    }

    private static func leggiSharedStrings(archive: Archive) -> [String] {
        guard let data = leggiFile(
            archive: archive,
            path: "xl/sharedStrings.xml"
        ),
        let xml = String(data: data, encoding: .utf8) else {
            return []
        }

        // sharedStrings può contenere <t> multipli nello stesso elemento <si>.
        // Per la nostra lettura è sufficiente ricomporre tutto il testo di ogni
        // <si>, evitando di perdere stringhe spezzate in più nodi XML.
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

        for siMatch in siRegex.matches(
            in: xml,
            range: NSRange(location: 0, length: ns.length)
        ) {
            let siXML = ns.substring(with: siMatch.range(at: 1))
            let siNS = siXML as NSString

            var testo = ""
            for tMatch in tRegex.matches(
                in: siXML,
                range: NSRange(location: 0, length: siNS.length)
            ) {
                testo += decodeXML(siNS.substring(with: tMatch.range(at: 1)))
            }

            result.append(testo)
        }

        return result
    }

    private static func leggiFile(archive: Archive, path: String) -> Data? {
        guard let entry = archive[path] else { return nil }

        var data = Data()

        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Parsing XML

    private static func estraiRigheXML(
        _ data: Data,
        sharedStrings: [String]
    ) -> [[String]] {
        guard let xml = String(data: data, encoding: .utf8) else {
            return []
        }

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

        for rowMatch in rowRegex.matches(
            in: xml,
            range: NSRange(location: 0, length: ns.length)
        ) {
            let rowXML = ns.substring(with: rowMatch.range(at: 1))
            let rowNS = rowXML as NSString

            var cells: [(Int, String)] = []

            for cellMatch in cellRegex.matches(
                in: rowXML,
                range: NSRange(location: 0, length: rowNS.length)
            ) {
                let attrs = rowNS.substring(with: cellMatch.range(at: 1))
                let body = rowNS.substring(with: cellMatch.range(at: 2))

                let ref = valoreAttributo(attrs, nome: "r") ?? "A1"
                let type = valoreAttributo(attrs, nome: "t")

                var testo = valoreTag(body, tag: "v") ?? ""

                if type == "s",
                   let index = Int(testo),
                   index >= 0,
                   index < sharedStrings.count {
                    testo = sharedStrings[index]
                }

                if type == "inlineStr" {
                    testo = valoreTag(body, tag: "t") ?? testo
                }

                let lettere = String(
                    ref.prefix { $0.isLetter }
                )

                cells.append(
                    (
                        columnIndex(lettere),
                        decodeXML(testo)
                    )
                )
            }

            guard let max = cells.map({ $0.0 }).max() else {
                continue
            }

            var row = Array(repeating: "", count: max + 1)

            for (index, value) in cells {
                row[index] = value
            }

            rows.append(row)
        }

        return rows
    }

    private static func valoreAttributo(
        _ testo: String,
        nome: String
    ) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: nome)

        let regex = try? NSRegularExpression(
            pattern: #"\b"# + escaped + #"="([^"]+)""#
        )

        guard let regex,
              let match = regex.firstMatch(
                in: testo,
                range: NSRange(
                    location: 0,
                    length: (testo as NSString).length
                )
              ) else {
            return nil
        }

        return (testo as NSString).substring(
            with: match.range(at: 1)
        )
    }

    private static func valoreTag(
        _ testo: String,
        tag: String
    ) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: tag)

        let regex = try? NSRegularExpression(
            pattern: #"<"# + escaped + #"[^>]*>(.*?)</"# + escaped + #">"#,
            options: [.dotMatchesLineSeparators]
        )

        guard let regex,
              let match = regex.firstMatch(
                in: testo,
                range: NSRange(
                    location: 0,
                    length: (testo as NSString).length
                )
              ) else {
            return nil
        }

        return (testo as NSString).substring(
            with: match.range(at: 1)
        )
    }

    private static func columnIndex(_ letters: String) -> Int {
        var value = 0

        for scalar in letters.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else {
                continue
            }

            value = value * 26 + Int(scalar.value - 64)
        }

        return max(0, value - 1)
    }

    // MARK: - Numeri e date

    private static func numeroDaStringa(_ valore: String) -> Double? {
        let s = valore
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard !s.isEmpty else { return nil }

        // Prima prova il formato normale usato da Excel/XML.
        if let n = Double(s) {
            return n
        }

        // Supporta anche 13,50 e 1.234,50.
        let europeo = s
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")

        return Double(europeo)
    }

    private static func dataDaValore(_ valore: String) -> Date? {
        let s = valore.trimmingCharacters(in: .whitespacesAndNewlines)

        let pattern = #"^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$"#

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(
                in: s,
                range: NSRange(s.startIndex..., in: s)
           ) {
            let ns = s as NSString

            let giorno = Int(
                ns.substring(with: match.range(at: 1))
            ) ?? 0

            let mese = Int(
                ns.substring(with: match.range(at: 2))
            ) ?? 0

            var anno = Int(
                ns.substring(with: match.range(at: 3))
            ) ?? 0

            if anno < 100 {
                anno += 2000
            }

            guard (1...31).contains(giorno),
                  (1...12).contains(mese),
                  (2000...2100).contains(anno) else {
                return nil
            }

            var components = DateComponents()
            components.day = giorno
            components.month = mese
            components.year = anno

            return Calendar(identifier: .gregorian).date(
                from: components
            )
        }

        // Excel usa normalmente il sistema data 1900.
        // 30000...60000 evita che una quantità venga interpretata
        // erroneamente come una data.
        if let seriale = Double(s),
           seriale >= 30000,
           seriale <= 60000 {
            var base = DateComponents()
            base.year = 1899
            base.month = 12
            base.day = 30

            let calendario = Calendar(identifier: .gregorian)

            guard let epoch = calendario.date(from: base) else {
                return nil
            }

            return calendario.date(
                byAdding: .day,
                value: Int(seriale.rounded()),
                to: epoch
            )
        }

        return nil
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
