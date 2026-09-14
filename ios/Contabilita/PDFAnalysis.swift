import Foundation
import PDFKit
import SwiftUI

struct AnalisiRigaPDF: Identifiable, Codable {
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

struct AnalisiPDF: Identifiable, Codable {
    let id: UUID
    var fileName: String
    var dataDocumento: Date?
    var righe: [AnalisiRigaPDF]
    var testoCompleto: String
    var analizzatoIl: Date
}

final class PDFAnalysisStore: ObservableObject {
    @Published private(set) var analisi: [AnalisiPDF] = []
    private let key = "contabilita_analisi_pdf_v1"

    init() { carica() }

    func carica() {
        if let data = UserDefaults.standard.data(forKey: key),
           let value = try? JSONDecoder().decode([AnalisiPDF].self, from: data) {
            analisi = value
        }
    }

    func analisiPer(fileName: String) -> AnalisiPDF? {
        analisi.first { $0.fileName == fileName }
    }

    @discardableResult
    func analizza(url: URL) -> AnalisiPDF {
        let document = PDFDocument(url: url)
        let text = document?.string ?? ""
        let result = PDFProspettoParser.parse(text: text, fileName: url.lastPathComponent)

        if let index = analisi.firstIndex(where: { $0.fileName == result.fileName }) {
            analisi[index] = result
        } else {
            analisi.append(result)
        }
        analisi.sort { $0.analizzatoIl > $1.analizzatoIl }
        salva()
        return result
    }

    private func salva() {
        if let data = try? JSONEncoder().encode(analisi) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum PDFProspettoParser {
    static func parse(text: String, fileName: String) -> AnalisiPDF {
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var rows: [AnalisiRigaPDF] = []
        for line in lines {
            if let row = parseRow(line) { rows.append(row) }
        }

        return AnalisiPDF(
            id: UUID(),
            fileName: fileName,
            dataDocumento: findDate(in: normalized),
            righe: rows,
            testoCompleto: normalized,
            analizzatoIl: Date()
        )
    }

    private static func parseRow(_ line: String) -> AnalisiRigaPDF? {
        let upper = line.uppercased()
        let ignored = ["TOTALE", "SUBTOTALE", "DATA", "DESCRIZIONE", "ARTICOLO", "QUANTITÀ", "QUANTITA", "PREZZO", "IMPORTO", "PERIODO", "RIEPILOGO"]
        if ignored.contains(where: { upper == $0 || upper.hasPrefix($0 + " ") }) { return nil }

        let pattern = #"^(.*?)(?:\s+)(\d{1,6})(?:\s+([0-9]+[.,][0-9]{1,4}))?(?:\s+([0-9]+[.,][0-9]{1,4}))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }

        func capture(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: line) else { return nil }
            return String(line[swiftRange]).trimmingCharacters(in: .whitespaces)
        }

        guard let nome = capture(1), !nome.isEmpty, let qString = capture(2), let q = Int(qString), q >= 0 else { return nil }
        let p = capture(3).flatMap(parseMoney)
        let t = capture(4).flatMap(parseMoney)
        return AnalisiRigaPDF(articolo: nome, quantita: q, prezzoUnitario: p, totale: t)
    }

    private static func parseMoney(_ value: String) -> Double? {
        let v = value.trimmingCharacters(in: .whitespaces)
        if v.contains(",") {
            return Double(v.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
        }
        if v.filter({ $0 == "." }).count > 1 {
            let parts = v.split(separator: ".")
            let decimal = parts.last!
            let integer = parts.dropLast().joined()
            return Double("\(integer).\(decimal)")
        }
        return Double(v)
    }

    private static func findDate(in text: String) -> Date? {
        let pattern = #"\b(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let raw = String(text[range])
        let formats = ["dd/MM/yyyy", "d/M/yyyy", "dd.MM.yyyy", "d.M.yyyy", "dd-MM-yyyy", "d-M-yyyy", "dd/MM/yy", "dd-MM-yy", "dd.MM.yy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

struct PDFAnalisiView: View {
    let file: URL
    @ObservedObject var store: PDFAnalysisStore
    @Environment(\.presentationMode) private var presentationMode
    @State private var risultato: AnalisiPDF?
    @State private var errore: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                PDFKitView(url: file)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let risultato = risultato ?? store.analisiPer(fileName: file.lastPathComponent) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ANALISI COMPLETATA")
                            .font(.headline)
                        Text("Righe trovate: \(risultato.righe.count)")
                            .font(.title3)
                        if let data = risultato.dataDocumento {
                            Text("Data: \(data.formatted(date: .numeric, time: .omitted))")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                }

                Button {
                    errore = nil
                    risultato = store.analizza(url: file)
                    if risultato?.righe.isEmpty == true && risultato?.testoCompleto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                        errore = "Questo PDF non contiene testo leggibile."
                    }
                } label: {
                    Text("CARICA E ANALIZZA")
                        .font(.system(size: 22, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }
            .navigationTitle("Analizza PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .alert("Analisi", isPresented: Binding(get: { errore != nil }, set: { if !$0 { errore = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errore ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }
}
