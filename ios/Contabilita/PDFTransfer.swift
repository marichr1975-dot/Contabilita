import Foundation
import SwiftUI
import UIKit

final class PDFTransferStore: ObservableObject {
    static let pdfPasteboardType = "com.gotrail.contabilita.pdf"
    static let namePasteboardType = "com.gotrail.contabilita.name"

    @Published private(set) var files: [URL] = []

    init() {
        ricarica()
    }

    private var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("PDFImportati", isDirectory: true)
    }

    func importaDaCondividi() {
        ricarica()

        let pasteboard = UIPasteboard.general
        guard let data = pasteboard.data(forPasteboardType: Self.pdfPasteboardType),
              data.count > 4,
              data.prefix(4).elementsEqual(Data([0x25, 0x50, 0x44, 0x46])) else {
            return
        }

        let name = pasteboard.value(forPasteboardType: Self.namePasteboardType) as? String ?? "prospetto"
        salva(data: data, nome: name)

        pasteboard.items = []
        ricarica()
    }

    func ricarica() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        files = ((try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
        .filter { $0.pathExtension.lowercased() == "pdf" }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func salva(data: Data, nome: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let base = nome
            .deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = base.isEmpty ? "prospetto" : base
        let url = folder.appendingPathComponent("\(safe)-\(UUID().uuidString.prefix(8)).pdf")

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // Il file resta sul pasteboard e verrà ritentato alla prossima apertura.
        }
    }
}

private extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}

struct PDFLocaliView: View {
    @ObservedObject var store: PDFTransferStore
    @ObservedObject var analysisStore: PDFAnalysisStore
    @Environment(\.presentationMode) private var presentationMode
    @State private var pdfSelezionato: URL?
    @State private var analisiInCorso = false
    @State private var errore: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if store.files.isEmpty {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.teal)
                    Text("Nessun PDF ricevuto").font(.title2)
                    Text("Da WhatsApp o File: Condividi → Contabilità.\nPoi riapri Contabilità.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    Text("PDF RICEVUTI")
                        .font(.title2).fontWeight(.semibold)
                        .padding(.top, 8)

                    List(store.files, id: \.self) { file in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                pdfSelezionato = file
                                errore = nil
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.fill").foregroundColor(.teal)
                                    Text(file.lastPathComponent).lineLimit(2).foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundColor(.secondary)
                                }
                            }

                            if pdfSelezionato == file {
                                Button {
                                    analizza(file)
                                } label: {
                                    HStack {
                                        Spacer()
                                        if analisiInCorso {
                                            ProgressView().padding(.trailing, 8)
                                            Text("ANALISI IN CORSO...")
                                        } else {
                                            Image(systemName: "wand.and.stars")
                                            Text("CARICA E ANALIZZA")
                                        }
                                        Spacer()
                                    }
                                    .font(.headline)
                                    .padding(.vertical, 12)
                                    .background(Color.teal.opacity(0.12))
                                    .cornerRadius(12)
                                }
                                .disabled(analisiInCorso)

                                if let existing = analysisStore.analisiPerFile(file) {
                                    Button("VEDI DATI ANALIZZATI") {
                                        pdfSelezionato = nil
                                        DispatchQueue.main.async {
                                            NotificationCenter.default.post(name: .contabilitaMostraAnalisi, object: existing)
                                        }
                                    }
                                    .font(.subheadline.weight(.semibold))
                                }

                                if let errore = errore {
                                    Text(errore).font(.footnote).foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listStyle(.plain)
                }
            }
            .padding(18)
            .navigationTitle("PDF azienda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .onAppear { store.importaDaCondividi(); store.ricarica() }
            .sheet(item: $pdfSelezionato) { file in
                PDFViewer(url: file)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func analizza(_ file: URL) {
        analisiInCorso = true
        errore = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = analysisStore.analizza(file)
            DispatchQueue.main.async {
                analisiInCorso = false
                if result == nil {
                    errore = "Impossibile leggere il testo del PDF. Se è una scansione fotografica, serve OCR."
                } else {
                    pdfSelezionato = nil
                    NotificationCenter.default.post(name: .contabilitaMostraAnalisi, object: result)
                }
            }
        }
    }
}

extension Notification.Name {
    static let contabilitaMostraAnalisi = Notification.Name("contabilitaMostraAnalisi")
}
