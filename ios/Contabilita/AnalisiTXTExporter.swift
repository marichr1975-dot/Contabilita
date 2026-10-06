import Foundation
import UIKit

struct AnalisiTXTExporter {
    static func creaTXT(archivio: Archivio, analysisStore: PDFAnalysisStore, fileAzienda: URL?) throws -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "dd/MM/yyyy"

        var out = "CONTABILITA - DATI ANALIZZATI\n"
        out += "========================================\n"
        out += "GENERATO: \(f.string(from: Date()))\n\n"

        out += "[1] NOSTRE BOLLETTE LETTE DALL'APP\n"
        out += "----------------------------------------\n"
        for b in archivio.bollette.sorted(by: { $0.data < $1.data }) {
            out += "DATA: \(f.string(from: b.data)) | ID: \(b.id.uuidString)\n"
            for l in b.lavorazioni {
                let nome = l.nome.trimmingCharacters(in: .whitespacesAndNewlines)
                let q = l.quantita.trimmingCharacters(in: .whitespacesAndNewlines)
                out += "  ARTICOLO: [\(nome)] | QUANTITA: [\(q)]\n"
            }
            out += "\n"
        }
        out += "TOTALE NOSTRE BOLLETTE: \(archivio.bollette.count)\n\n"

        out += "[2] FILE AZIENDA CARICATO\n"
        out += "----------------------------------------\n"
        if let fileAzienda {
            out += "NOME FILE: \(fileAzienda.lastPathComponent)\n"
            out += "ESTENSIONE: \(fileAzienda.pathExtension)\n"
        } else {
            out += "NESSUN FILE AZIENDA DISPONIBILE\n"
        }
        out += "\n"

        out += "[3] DATI AZIENDA INTERPRETATI DALL'APP\n"
        out += "----------------------------------------\n"
        let giorni = analysisStore.giorniAzienda().sorted(by: { $0.date < $1.date })
        for day in giorni {
            out += "DATA: \(f.string(from: day.date)) | RIGHE: \(day.rows.count)\n"
            for r in day.rows {
                let prezzo = r.unitPrice.map { String(format: "%.4f", $0) } ?? "-"
                let totale = r.total.map { String(format: "%.4f", $0) } ?? "-"
                out += "  ARTICOLO: [\(r.article)] | QUANTITA: [\(r.quantity)] | PREZZO: [\(prezzo)] | TOTALE: [\(totale)]\n"
            }
            out += "\n"
        }
        out += "TOTALE GIORNI AZIENDA: \(giorni.count)\n"
        out += "TOTALE PEZZI AZIENDA: \(giorni.reduce(0) { $0 + $1.rows.reduce(0) { $0 + $1.quantity } })\n\n"

        out += "[4] CONFRONTO PER DATA E ARTICOLO\n"
        out += "----------------------------------------\n"
        var dateSet = Set<Date>()
        let cal = Calendar(identifier: .gregorian)
        for b in archivio.bollette { dateSet.insert(cal.startOfDay(for: b.data)) }
        for d in giorni { dateSet.insert(cal.startOfDay(for: d.date)) }

        func norm(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for date in dateSet.sorted() {
            var nostre: [String:Int] = [:]
            for b in archivio.bollette where cal.isDate(b.data, inSameDayAs: date) {
                for l in b.lavorazioni {
                    let n = norm(l.nome)
                    let q = Int(l.quantita.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    if !n.isEmpty && q > 0 { nostre[n, default: 0] += q }
                }
            }
            var azienda: [String:Int] = [:]
            for d in giorni where cal.isDate(d.date, inSameDayAs: date) {
                for r in d.rows {
                    let n = norm(r.article)
                    if !n.isEmpty && r.quantity > 0 { azienda[n, default: 0] += r.quantity }
                }
            }
            out += "DATA: \(f.string(from: date))\n"
            out += "  NOSTRE: \(nostre.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "))\n"
            out += "  AZIENDA: \(azienda.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "))\n"
            out += "  STATO: \(nostre == azienda ? "OK" : "DIFFERENZA")\n\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CONTABILITA_DATI_ANALIZZATI_\(Int(Date().timeIntervalSince1970)).txt")
        try out.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

struct TXTShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
