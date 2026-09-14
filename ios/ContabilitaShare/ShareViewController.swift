import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let pdfType = "com.gotrail.contabilita.pdf"
    private let nameType = "com.gotrail.contabilita.name"
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
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.data.identifier)
        }) else {
            termina()
            return
        }

        handled = true
        carica(provider: provider)
    }

    private func carica(provider: NSItemProvider) {
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { [weak self] url, _ in
                if let url = url, let data = try? Data(contentsOf: url), self?.salvaSuPasteboard(data: data, nome: url.lastPathComponent) == true {
                    self?.terminaSulMain()
                } else {
                    self?.caricaComeDati(provider: provider)
                }
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                if let url = item as? URL,
                   let data = try? Data(contentsOf: url),
                   self?.salvaSuPasteboard(data: data, nome: url.lastPathComponent) == true {
                    self?.terminaSulMain()
                } else {
                    self?.caricaComeDati(provider: provider)
                }
            }
            return
        }

        caricaComeDati(provider: provider)
    }

    private func caricaComeDati(provider: NSItemProvider) {
        let type = provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
            ? UTType.pdf.identifier
            : UTType.data.identifier

        provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, _ in
            guard let self = self, let data = data else {
                self?.terminaSulMain()
                return
            }
            _ = self.salvaSuPasteboard(data: data, nome: "prospetto.pdf")
            self.terminaSulMain()
        }
    }

    private func salvaSuPasteboard(data: Data, nome: String) -> Bool {
        guard data.count > 4,
              data.prefix(4).elementsEqual(Data([0x25, 0x50, 0x44, 0x46])) else {
            return false
        }

        UIPasteboard.general.setItems([
            [
                pdfType: data,
                nameType: (nome as NSString).deletingPathExtension
            ]
        ], options: [
            .expirationDate: Date(timeIntervalSinceNow: 15 * 60),
            .localOnly: false
        ])
        return true
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
