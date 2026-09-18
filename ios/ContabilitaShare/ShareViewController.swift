import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private let companyFileType = "com.gotrail.contabilita.companyfile"
    private let nameType = "com.gotrail.contabilita.name"
    private var handled = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.backgroundColor = .systemBackground
        riceviFile()
    }

    private func riceviFile() {
        guard !handled else { return }
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            termina(); return
        }

        let providers = items.flatMap { $0.attachments ?? [] }

        // IMPORTANTE: Excel prima di PDF.
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.spreadsheet.identifier)
        }) ?? providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }) ?? providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            termina(); return
        }

        handled = true

        if provider.hasItemConformingToTypeIdentifier(UTType.spreadsheet.identifier) {
            carica(provider, type: UTType.spreadsheet.identifier)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            carica(provider, type: UTType.pdf.identifier)
        } else {
            carica(provider, type: UTType.fileURL.identifier)
        }
    }

    private func carica(_ provider: NSItemProvider, type: String) {
        provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, error in
            guard let self else { return }

            if let url, error == nil, let data = try? Data(contentsOf: url) {
                let ok = self.salvaSuPasteboard(data: data, nome: url.lastPathComponent)
                DispatchQueue.main.async {
                    if ok {
                        self.mostraPulsanteApri()
                    } else {
                        self.termina()
                    }
                }
                return
            }

            provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, error in
                guard let self, let data, error == nil else {
                    DispatchQueue.main.async { self?.termina() }
                    return
                }

                guard let nome = self.nomeDaProvider(provider), !nome.isEmpty else {
                    DispatchQueue.main.async { self.termina() }
                    return
                }
                let ok = self.salvaSuPasteboard(data: data, nome: nome)

                DispatchQueue.main.async {
                    if ok {
                        self.mostraPulsanteApri()
                    } else {
                        self.termina()
                    }
                }
            }
        }
    }

    private func nomeDaProvider(_ provider: NSItemProvider) -> String? {
        if let suggested = provider.suggestedName, !suggested.isEmpty {
            return suggested
        }
        return nil
    }

    private func salvaSuPasteboard(data: Data, nome: String) -> Bool {
        guard data.count > 4 else { return false }

        // Cancella il contenuto precedente: non deve mai poter riapparire
        // un vecchio PDF quando arriva un nuovo Excel.
        UIPasteboard.general.items = []

        UIPasteboard.general.setItems([
            [
                companyFileType: data,
                nameType: nome
            ]
        ], options: [
            .expirationDate: Date(timeIntervalSinceNow: 15 * 60),
            .localOnly: false
        ])

        return true
    }

    private func mostraPulsanteApri() {
        view.subviews.forEach { $0.removeFromSuperview() }

        let label = UILabel()
        label.text = "File ricevuto in Contabilità"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 0

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
            DispatchQueue.main.async {
                if success {
                    self?.termina()
                }
            }
        }
    }

    private func termina() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
