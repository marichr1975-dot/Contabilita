import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let groupID = "group.com.gotrail.contabilita"
    private var handled = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.backgroundColor = .systemBackground
        riceviPDF()
    }

    private func riceviPDF() {
        guard !handled else { return }
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            termina()
            return
        }

        let providers = items.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else {
            termina()
            return
        }

        guard let provider = providers.first(where: { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ||
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
            provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) ||
            provider.hasItemConformingToTypeIdentifier(UTType.item.identifier)
        }) else {
            termina()
            return
        }

        handled = true
        carica(provider: provider)
    }

    private func carica(provider: NSItemProvider) {
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { [weak self] url, error in
                if let url = url, error == nil, self?.salvaPDFDaURL(url) == true {
                    self?.terminaSulMain()
                    return
                }
                self?.caricaComeDati(provider: provider)
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                if let url = item as? URL, error == nil, self?.salvaPDFDaURL(url) == true {
                    self?.terminaSulMain()
                    return
                }
                self?.caricaComeDati(provider: provider)
            }
            return
        }

        caricaComeDati(provider: provider)
    }

    private func caricaComeDati(provider: NSItemProvider) {
        let type = provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ? UTType.pdf.identifier : UTType.data.identifier
        provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, error in
            guard let self = self, let data = data, error == nil else {
                self?.terminaSulMain()
                return
            }
            guard data.count > 4, data.prefix(4).elementsEqual(Data([0x25, 0x50, 0x44, 0x46])) else {
                self.terminaSulMain()
                return
            }
            self.salvaPDFDaDati(data)
            self.terminaSulMain()
        }
    }

    @discardableResult
    private func salvaPDFDaURL(_ sourceURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: sourceURL) else { return false }
        guard data.count > 4, data.prefix(4).elementsEqual(Data([0x25, 0x50, 0x44, 0x46])) else { return false }
        salvaPDFDaDati(data, nome: sourceURL.deletingPathExtension().lastPathComponent)
        return true
    }

    private func salvaPDFDaDati(_ data: Data, nome: String = "prospetto") {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { return }

        let folder = container.appendingPathComponent("PDFImportati", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let baseName = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = baseName.isEmpty ? "prospetto" : baseName
        let destination = folder.appendingPathComponent(
            "\(safeName)-\(UUID().uuidString.prefix(8)).pdf"
        )

        do {
            try data.write(to: destination, options: .atomic)
            UserDefaults(suiteName: groupID)?.set(Date().timeIntervalSince1970, forKey: "pdf_importato_data")
        } catch {
            // Se il salvataggio fallisce, l'app principale non vede alcun PDF.
        }
    }

    private func terminaSulMain() {
        DispatchQueue.main.async { [weak self] in
            self?.termina()
        }
    }

    private func termina() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
