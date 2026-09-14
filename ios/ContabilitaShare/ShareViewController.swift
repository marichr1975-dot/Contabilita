import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private let groupID = "group.com.gotrail.contabilita"
    private var didStart = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.backgroundColor = .systemBackground
        guard !didStart else { return }
        didStart = true
        riceviPDF()
    }

    private func riceviPDF() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            termina()
            return
        }

        let providers = items.flatMap { $0.attachments ?? [] }

        // Preferenza: PDF vero, poi file URL, poi item generico.
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }) {
            caricaPDF(provider)
            return
        }

        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) {
            caricaFileURL(provider)
            return
        }

        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.item.identifier)
        }) {
            caricaItemGenerico(provider)
            return
        }

        termina()
    }

    private func caricaPDF(_ provider: NSItemProvider) {
        provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) {
            [weak self] url, error in

            if let url, error == nil,
               self?.salvaPDFDaURL(url) == true {
                self?.terminaSulMain()
                return
            }

            // Alcune app (WhatsApp, File, Mail ecc.) consegnano il PDF come Data.
            provider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) {
                [weak self] data, _ in

                guard let self, let data,
                      self.isPDF(data) else {
                    self?.terminaSulMain()
                    return
                }

                self.salvaPDFDaDati(data, nome: "prospetto")
                self.terminaSulMain()
            }
        }
    }

    private func caricaFileURL(_ provider: NSItemProvider) {
        provider.loadItem(
            forTypeIdentifier: UTType.fileURL.identifier,
            options: nil
        ) { [weak self] item, error in

            if let url = item as? URL, error == nil,
               self?.salvaPDFDaURL(url) == true {
                self?.terminaSulMain()
                return
            }

            // Alcuni provider restituiscono un Data invece di URL.
            if let data = item as? Data, self?.isPDF(data) == true {
                self?.salvaPDFDaDati(data, nome: "prospetto")
                self?.terminaSulMain()
                return
            }

            self?.caricaItemGenerico(provider)
        }
    }

    private func caricaItemGenerico(_ provider: NSItemProvider) {
        provider.loadItem(
            forTypeIdentifier: UTType.item.identifier,
            options: nil
        ) { [weak self] item, error in

            guard let self, error == nil else {
                self?.terminaSulMain()
                return
            }

            if let url = item as? URL, self.salvaPDFDaURL(url) {
                self.terminaSulMain()
                return
            }

            if let data = item as? Data, self.isPDF(data) {
                self.salvaPDFDaDati(data, nome: "prospetto")
                self.terminaSulMain()
                return
            }

            // Ultimo tentativo: chiediamo esplicitamente il PDF.
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                self.caricaPDF(provider)
            } else {
                self.terminaSulMain()
            }
        }
    }

    private func isPDF(_ data: Data) -> Bool {
        data.count >= 4 &&
        data.prefix(4).elementsEqual(Data([0x25, 0x50, 0x44, 0x46]))
    }

    @discardableResult
    private func salvaPDFDaURL(_ sourceURL: URL) -> Bool {
        // loadFileRepresentation restituisce un file temporaneo.
        // Lo leggiamo immediatamente mentre il provider garantisce l'accesso.
        guard let data = try? Data(contentsOf: sourceURL),
              isPDF(data) else {
            return false
        }

        let nome = sourceURL
            .deletingPathExtension()
            .lastPathComponent

        salvaPDFDaDati(
            data,
            nome: nome.isEmpty ? "prospetto" : nome
        )
        return true
    }

    private func salvaPDFDaDati(_ data: Data, nome: String) {
        guard isPDF(data) else { return }

        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else {
            return
        }

        let folder = container.appendingPathComponent(
            "PDFImportati",
            isDirectory: true
        )

        do {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )

            let base = nome
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let safeName = base.isEmpty ? "prospetto" : base

            let destination = folder.appendingPathComponent(
                "\(safeName)-\(UUID().uuidString.prefix(8)).pdf"
            )

            try data.write(to: destination, options: .atomic)

            UserDefaults(suiteName: groupID)?.set(
                Date().timeIntervalSince1970,
                forKey: "pdf_importato_data"
            )
        } catch {
            // Nessuna chiusura anticipata: il chiamante termina comunque l'estensione.
        }
    }

    private func terminaSulMain() {
        DispatchQueue.main.async { [weak self] in
            self?.termina()
        }
    }

    private func termina() {
        extensionContext?.completeRequest(
            returningItems: nil,
            completionHandler: nil
        )
    }
}
