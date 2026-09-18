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

        guard let name = (pasteboard.value(forPasteboardType: Self.namePasteboardType) as? String),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ricarica()
            return
        }

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
        guard !base.isEmpty else { return }

        let url = folder.appendingPathComponent("\(base).\(ext)")

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("Errore salvataggio file azienda: \(error)")
        }
    }
}
