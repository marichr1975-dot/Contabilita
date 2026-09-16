import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let companyFileType = "com.gotrail.contabilita.companyfile"
    private let pdfType = "com.gotrail.contabilita.pdf"
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
            termina()
            return
        }

        let providers = items.flatMap { $0.attachments ?? [] }

        // Preferisci Excel se il file condiviso è un foglio di calcolo.
        // È importante: non chiediamo mai a Mail di trasformare l'xlsx in PDF.
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.spreadsheet.identifier) ||
            $0.hasItemConformingToTypeIdentifier("com.microsoft.excel.xlsx")
        }) {
            handled = true
            carica(provider: provider, preferenza: .excel)
            return
        }

        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }) {
            handled = true
            carica(provider: provider, preferenza: .pdf)
            return
        }

        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.data.identifier)
        }) {
            handled = true
            carica(provider: provider, preferenza: .generico)
            return
        }

        termina()
    }

    private enum Preferenza { case excel, pdf, generico }

    private func carica(provider: NSItemProvider, preferenza: Preferenza) {
        let type: String

        switch preferenza {
        case .excel:
            type = provider.hasItemConformingToTypeIdentifier(UTType.spreadsheet.identifier)
                ? UTType.spreadsheet.identifier
                : "com.microsoft.excel.xlsx"
        case .pdf:
            type = UTType.pdf.identifier
        case .generico:
            type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                ? UTType.fileURL.identifier
                : UTType.data.identifier
        }

        provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, _ in
            if let url, let data = try? Data(contentsOf: url), data.count > 4 {
                self?.salvaSuPasteboard(data: data, nome: url.lastPathComponent)
                self?.fileSalvato(nome: url.lastPathComponent)
                return
            }

            // Alcuni provider (tra cui Mail in certe versioni iOS) non espongono
            // loadFileRepresentation per Excel. In quel caso passiamo ai dati.
            self?.caricaComeDati(provider: provider, preferenza: preferenza)
        }
    }

    private func caricaComeDati(provider: NSItemProvider, preferenza: Preferenza) {
        let type: String
        switch preferenza {
        case .excel:
            type = provider.hasItemConformingToTypeIdentifier(UTType.spreadsheet.identifier)
                ? UTType.spreadsheet.identifier
                : "com.microsoft.excel.xlsx"
        case .pdf:
            type = UTType.pdf.identifier
        case .generico:
            type = UTType.data.identifier
        }

        provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, _ in
            guard let self, let data, data.count > 4 else {
                DispatchQueue.main.async { self?.mostraErrore() }
                return
            }

            let nome: String
            switch preferenza {
            case .excel:
                nome = "prospetto.xlsx"
            case .pdf:
                nome = "prospetto.pdf"
            case .generico:
                nome = "prospetto"
            }

            self.salvaSuPasteboard(data: data, nome: nome)
            self.fileSalvato(nome: nome)
        }
    }

    @discardableResult
    private func salvaSuPasteboard(data: Data, nome: String) -> Bool {
        guard data.count > 4 else { return false }

        let ext = (nome as NSString).pathExtension.lowercased()
        var item: [String: Any] = [
            companyFileType: data,
            nameType: nome
        ]

        // Il vecchio codice metteva OGNI file anche sotto il tipo PDF.
        // Questo faceva sembrare un Excel un PDF ai provider e rendeva ambiguo
        // il trasferimento. Ora il tipo PDF viene usato solo per un vero PDF.
        if ext == "pdf" {
            item[pdfType] = data
        }

        UIPasteboard.general.setItems(
            [item],
            options: [
                .expirationDate: Date(timeIntervalSinceNow: 15 * 60),
                .localOnly: false
            ]
        )
        return true
    }

    private func fileSalvato(nome: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let label = UILabel()
            label.text = "File ricevuto:\n\(nome)"
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .headline)
            label.textAlignment = .center

            let button = UIButton(type: .system)
            button.setTitle("APRI CONTABILITÀ", for: .normal)
            button.titleLabel?.font = .boldSystemFont(ofSize: 18)
            button.addTarget(self, action: #selector(apriContabilitaManuale), for: .touchUpInside)

            self.view.subviews.forEach { $0.removeFromSuperview() }
            let stack = UIStackView(arrangedSubviews: [label, button])
            stack.axis = .vertical
            stack.spacing = 24
            stack.alignment = .fill
            stack.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24),
                stack.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
            ])
        }
    }

    private func mostraErrore() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let label = UILabel()
            label.text = "Impossibile leggere il file condiviso."
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = .preferredFont(forTextStyle: .headline)

            let button = UIButton(type: .system)
            button.setTitle("CHIUDI", for: .normal)
            button.addTarget(self, action: #selector(chiudi), for: .touchUpInside)

            self.view.subviews.forEach { $0.removeFromSuperview() }
            let stack = UIStackView(arrangedSubviews: [label, button])
            stack.axis = .vertical
            stack.spacing = 20
            stack.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24),
                stack.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
            ])
        }
    }

    @objc private func apriContabilitaManuale() {
        guard let url = URL(string: "contabilita://import") else { return }
        extensionContext?.open(url) { [weak self] success in
            if success {
                DispatchQueue.main.async { self?.termina() }
            }
        }
    }

    @objc private func chiudi() {
        termina()
    }

    private func termina() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
