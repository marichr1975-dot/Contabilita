import Foundation
import SwiftUI
import UIKit

enum AnalisiTXTExporter {
    static func creaTXT(archivio: Archivio, analysisStore: PDFAnalysisStore, fileStore: PDFTransferStore) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "dd/MM/yyyy"

        func normalizza(_ value: String) -> String {
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func nostroPerData(_ date: Date) -> [String: Int] {
            var cal = Calendar(identifier: .gregorian)
            cal.locale = Locale(identifier: "it_IT")
            var result: [String: Int] = [:]
            for b in archivio.bollette where cal.isDate(b.data, inSameDayAs: date) {
                for l in b.lavorazioni {
                    let nome = normalizza(l.nome)
                    let q = Int(l.quantita.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    if !nome.isEmpty { result[nome, default: 0] += q }
                }
            }
            return result
        }

        func aziendaPerData(_ date: Date) -> [String: Int] {
            var cal = Calendar(identifier: .gregorian)
            cal.locale = Locale(identifier: "it_IT")
            var result: [String: Int] = [:]
            for d in analysisStore.giorniAzienda() where cal.isDate(d.date, inSameDayAs: date) {
                for r in d.rows {
                    let nome = normalizza(r.article)
                    if !nome.isEmpty { result[nome, default: 0] += r.quantity }
                }
            }
            return result
        }

        var dates = Set<Date>()
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "it_IT")
        archivio.bollette.forEach { dates.insert(cal.startOfDay(for: $0.data)) }
        analysisStore.giorniAzienda().forEach { dates.insert(cal.startOfDay(for: $0.date)) }

        var text = "CONTABILITA - DATI ANALIZZATI\n"
        text += "Generato: \(Date().formatted(date: .numeric, time: .standard))\n\n"
        text += "FILE AZIENDA:\n"
        if let file = fileStore.files.first {
            text += "- \(file.lastPathComponent)\n"
        } else {
            text += "- NESSUN FILE\n"
        }

        text += "\nNOSTRE BOLLETTE: \(archivio.bollette.count)\n"
        for b in archivio.bollette.sorted(by: { $0.data < $1.data }) {
            text += "  \(formatter.string(from: b.data)) | \(b.lavorazioni.count) righe\n"
            for l in b.lavorazioni {
                text += "    \(l.nome) = \(l.quantita)\n"
            }
        }

        text += "\nDATI AZIENDA ESTRATTI: \(analysisStore.giorniAzienda().count) DATE\n"
        for d in analysisStore.giorniAzienda().sorted(by: { $0.date < $1.date }) {
            text += "  \(formatter.string(from: d.date)) | \(d.rows.count) righe\n"
            for r in d.rows {
                let prezzo = r.unitPrice.map { String(format: "%.4f", $0) } ?? "-"
                let totale = r.total.map { String(format: "%.2f", $0) } ?? "-"
                text += "    \(r.article) = \(r.quantity) | prezzo=\(prezzo) | totale=\(totale)\n"
            }
        }

        text += "\nCONFRONTO PER DATA + ARTICOLO\n"
        text += "========================================\n"
        for date in dates.sorted() {
            let ours = nostroPerData(date)
            let company = aziendaPerData(date)
            let names = Set(ours.keys).union(company.keys).sorted()
            let dateText = formatter.string(from: date)
            let hasOur = !ours.isEmpty
            let hasCompany = !company.isEmpty
            text += "\nDATA \(dateText) | NOSTRA=\(hasOur ? "SI" : "NO") | AZIENDA=\(hasCompany ? "SI" : "NO")\n"
            if names.isEmpty {
                text += "  NESSUN ARTICOLO\n"
            } else {
                for name in names {
                    let n = ours[name] ?? 0
                    let a = company[name] ?? 0
                    let esito = n == a ? "OK" : "DIFFERENZA"
                    text += "  \(name) | nostra=\(n) | azienda=\(a) | \(esito)\n"
                }
            }
            let totalN = ours.values.reduce(0, +)
            let totalA = company.values.reduce(0, +)
            text += "  TOTALE DATA | nostra=\(totalN) | azienda=\(totalA) | \(totalN == totalA ? "OK" : "DIFFERENZA")\n"
        }

        text += "\nTOTALI GENERALI\n"
        text += "Nostro: \(archivio.bollette.reduce(0) { $0 + $1.lavorazioni.reduce(0) { $0 + (Int($1.quantita.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) } })\n"
        text += "Azienda: \(analysisStore.giorniAzienda().reduce(0) { $0 + $1.rows.reduce(0) { $0 + $1.quantity } })\n"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CONTABILITA_DATI_ANALIZZATI.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Errore creazione TXT: \(error)")
            return nil
        }
    }
}

struct TXTShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: UIViewControllerRepresentableContext<TXTShareSheet>) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<TXTShareSheet>) {}
}
