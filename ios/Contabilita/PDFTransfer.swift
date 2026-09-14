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
    @Environment(\.presentationMode) private var presentationMode
    @State private var pdfDaMostrare: URL?

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                if store.files.isEmpty {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.teal)
                    Text("Nessun PDF ricevuto")
                        .font(.title2)
                    Text("Da WhatsApp o File: Condividi → Contabilità.\nPoi riapri Contabilità.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    Text("PDF RICEVUTI")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top, 8)

                    List(store.files, id: \.self) { file in
                        Button {
                            pdfDaMostrare = file
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.teal)
                                Text(file.lastPathComponent)
                                    .lineLimit(2)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
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
            .onAppear { store.importaDaCondividi() }
            .sheet(item: $pdfDaMostrare) { file in
                PDFViewer(url: file)
            }
        }
        .navigationViewStyle(.stack)
    }
}
