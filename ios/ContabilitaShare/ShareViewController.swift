import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let pdfType = "com.gotrail.contabilita.pdf"
    private let nameType = "com.gotrail.contabilita.name"
    private var handled = false
    private var saved = false

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
                    self?.pdfSalvato()
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
                    self?.pdfSalvato()
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
                self?.pdfSalvato()
                return
            }
            _ = self.salvaSuPasteboard(data: data, nome: "prospetto.pdf")
            self.pdfSalvato()
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

    private func pdfSalvato() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.saved = true
            self.apriContabilita()
        }
    }

    private func apriContabilita() {
        guard let url = URL(string: "contabilita://import") else {
            mostraPulsanteApri()
            return
        }

        extensionContext?.open(url) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.termina()
                } else {
                    self?.mostraPulsanteApri()
                }
            }
        }
    }

    private func mostraPulsanteApri() {
        view.subviews.forEach { $0.removeFromSuperview() }

        let label = UILabel()
        label.text = "PDF ricevuto in Contabilità"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center

        let button = UIButton(type: .system)
        button.setTitle("APRI CONTABILITÀ", for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 18)
        button.addTarget(self, action: #selector(apriContabilitaManuale), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical
        stack.spacing = 24
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func apriContabilitaManuale() {
        guard let url = URL(string: "contabilita://import") else { return }
        extensionContext?.open(url) { [weak self] success in
            if success {
                DispatchQueue.main.async { self?.termina() }
            }
        }
    }

    private func termina() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
