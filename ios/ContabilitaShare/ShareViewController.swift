import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let groupID = "group.com.gotrail.contabilita"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Invio PDF a Contabilità…"
        label.font = .systemFont(ofSize: 22, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        riceviPDF()
    }

    private func riceviPDF() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            termina()
            return
        }

        let providers = items.flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }) else {
            termina()
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { [weak self] url, error in
            guard let self = self, let url = url, error == nil else {
                DispatchQueue.main.async { self?.termina() }
                return
            }
            self.salvaPDF(url)
        }
    }

    private func salvaPDF(_ sourceURL: URL) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else {
            DispatchQueue.main.async { self.termina() }
            return
        }

        let folder = container.appendingPathComponent("PDFImportati", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let safeName = baseName.isEmpty ? "prospetto" : baseName
        let destination = folder.appendingPathComponent(
            "\(safeName)-\(UUID().uuidString.prefix(8)).pdf"
        )

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            UserDefaults(suiteName: groupID)?.set(true, forKey: "pdf_importato")
        } catch {
            // Il file viene ignorato se la copia non riesce.
        }

        DispatchQueue.main.async { self.termina() }
    }

    private func termina() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
