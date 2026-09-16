import Foundation
import SwiftUI
import UIKit

final class PDFTransferStore: ObservableObject {
    static let companyFilePasteboardType = "com.gotrail.contabilita.companyfile"
    static let namePasteboardType = "com.gotrail.contabilita.name"

    @Published private(set) var files: [URL] = []

    init() {
        ricarica()
    }

    private var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FileAzienda", isDirectory: true)
    }

    func importaDaCondividi() {
        let pasteboard = UIPasteboard.general

        guard let data = pasteboard.data(forPasteboardType: Self.companyFilePasteboardType),
              data.count > 4 else {
            ricarica()
            return
        }

        let name = (pasteboard.value(forPasteboardType: Self.namePasteboardType) as? String)
            ?? "prospetto.xlsx"

        // Un nuovo import sostituisce quello precedente.
        eliminaTuttiIFileLocali()

        salva(data: data, nome: name)

        // Evita che lo stesso trasferimento venga importato nuovamente
        // ogni volta che la scena torna active.
        pasteboard.items = []
        ricarica()
    }

    func elimina(file: URL) {
        try? FileManager.default.removeItem(at: file)
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
        .filter {
            ["pdf", "xlsx", "xls"].contains($0.pathExtension.lowercased())
        }
        .sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func eliminaTuttiIFileLocali() {
        let fm = FileManager.default
        guard let oldFiles = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in oldFiles {
            try? fm.removeItem(at: file)
        }
    }

    private func salva(data: Data, nome: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let originalExtension = (nome as NSString).pathExtension.lowercased()
        let ext = ["xlsx", "xls", "pdf"].contains(originalExtension) ? originalExtension : "xlsx"

        let base = (nome as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeBase = base.isEmpty ? "prospetto" : base

        let url = folder.appendingPathComponent("\(safeBase).\(ext)")

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("Errore salvataggio file azienda: \(error)")
        }
    }
}

struct PDFImportatiView: View {
    @ObservedObject var store: PDFTransferStore
    @ObservedObject var analysisStore: PDFAnalysisStore
    @Environment(\.presentationMode) private var presentationMode
    @State private var pdfDaMostrare: URL?
    @State private var messaggioCaricamento = ""
    @State private var mostraConfermaCaricamento = false

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                if store.files.isEmpty {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.teal)
                    Text("Nessun file aziendale")
                        .font(.title2)
                    Text("Da Mail o File: Condividi → Contabilità")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    Text("FILE AZIENDA")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top, 8)

                    List(store.files, id: \.self) { file in
                        HStack(spacing: 10) {
                            Image(systemName: file.pathExtension.lowercased() == "pdf"
                                  ? "doc.richtext.fill"
                                  : "tablecells.fill")
                                .foregroundColor(.teal)

                            Text(file.lastPathComponent)
                                .lineLimit(2)

                            Spacer()

                            Button("CARICA") {
                                analysisStore.analizza(file: file, bollette: [])
                                messaggioCaricamento = "✓ FILE CARICATO E ANALIZZATO"
                                mostraConfermaCaricamento = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)

                            if file.pathExtension.lowercased() == "pdf" {
                                Button("MOSTRA PDF") {
                                    pdfDaMostrare = file
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Text("EXCEL")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Button("CANCELLA") {
                                store.elimina(file: file)
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                        }
                        .padding(.vertical, 8)
                    }
                    .listStyle(.plain)
                }
            }
            .padding(18)
            .navigationTitle("File azienda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .onAppear { store.ricarica() }
            .sheet(item: $pdfDaMostrare) { file in
                PDFViewer(url: file)
            }
            .alert(messaggioCaricamento, isPresented: $mostraConfermaCaricamento) {
                Button("OK", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
    }
}
