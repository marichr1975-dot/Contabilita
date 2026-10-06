import Foundation
import ZIPFoundation

/// Crea un XLSX semplice e leggibile sia dall'app sia da Excel/ChatGPT.
/// Il file viene rigenerato ad ogni modifica dell'archivio.
enum NostreBolletteExcel {
    static func creaFile(
        bollette: [Bolletta],
        nomiLavorazioni: [String],
        url: URL
    ) throws {
        var articoli: [String] = []
        var indice: [String: Int] = [:]

        func chiave(_ nome: String) -> String {
            nome.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for bolletta in bollette.sorted(by: { $0.data < $1.data }) {
            for lavoro in bolletta.lavorazioni {
                let nome = lavoro.nome.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !nome.isEmpty else { continue }
                let key = chiave(nome)
                if indice[key] == nil {
                    indice[key] = articoli.count
                    articoli.append(nome)
                }
            }
        }

        // Se l'archivio non contiene ancora lavorazioni, manteniamo comunque
        // i nomi conosciuti dall'app per rendere il file immediatamente utile.
        if articoli.isEmpty {
            for nome in nomiLavorazioni {
                let n = nome.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = chiave(n)
                guard !n.isEmpty, indice[key] == nil else { continue }
                indice[key] = articoli.count
                articoli.append(n)
            }
        }

        var rows: [[Cell]] = []
        rows.append([.string("DATA")] + articoli.map { .string($0) } + [.string("TOTALE PEZZI")])

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "dd/MM/yyyy"

        for bolletta in bollette.sorted(by: { $0.data < $1.data }) {
            var quantita: [String: Int] = [:]

            for lavoro in bolletta.lavorazioni {
                let nome = lavoro.nome.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !nome.isEmpty else { continue }
                let q = Int(lavoro.quantita.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                guard q != 0 else { continue }
                quantita[chiave(nome), default: 0] += q
            }

            let valori = articoli.map { articolo in
                Cell.number(quantita[chiave(articolo)] ?? 0)
            }
            let totale = quantita.values.reduce(0, +)

            rows.append([.string(formatter.string(from: bolletta.data))] + valori + [.number(totale)])
        }

        let sheet = makeSheetXML(rows: rows)
        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Bollette" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """

        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """

        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """

        try? FileManager.default.removeItem(at: url)
        let archive = try Archive(url: url, accessMode: .create)

        try add(Data(contentTypes.utf8), path: "[Content_Types].xml", to: archive)
        try add(Data(rootRels.utf8), path: "_rels/.rels", to: archive)
        try add(Data(workbook.utf8), path: "xl/workbook.xml", to: archive)
        try add(Data(workbookRels.utf8), path: "xl/_rels/workbook.xml.rels", to: archive)
        try add(Data(sheet.utf8), path: "xl/worksheets/sheet1.xml", to: archive)
    }

    private enum Cell {
        case string(String)
        case number(Int)
    }

    private static func add(_ data: Data, path: String, to archive: Archive) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            return data.subdata(in: start..<end)
        }
    }

    private static func makeSheetXML(rows: [[Cell]]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
        """

        for (rowIndex, row) in rows.enumerated() {
            let r = rowIndex + 1
            xml += "<row r=\"\(r)\">"

            for (columnIndex, cell) in row.enumerated() {
                let ref = "\(columnName(columnIndex))\(r)"
                switch cell {
                case .string(let value):
                    xml += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(escapeXML(value))</t></is></c>"
                case .number(let value):
                    xml += "<c r=\"\(ref)\"><v>\(value)</v></c>"
                }
            }

            xml += "</row>"
        }

        xml += """
          </sheetData>
        </worksheet>
        """
        return xml
    }

    private static func columnName(_ index: Int) -> String {
        var n = index + 1
        var result = ""

        while n > 0 {
            let remainder = (n - 1) % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            n = (n - 1) / 26
        }

        return result
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
