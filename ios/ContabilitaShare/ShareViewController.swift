import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private let appGroup = "group.com.gotrail.contabilita"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        receiveIncomingFile()
    }

    private func receiveIncomingFile() {
        guard let extensionContext else {
            finish()
            return
        }

        let items = extensionContext.inputItems.compactMap { $0 as? NSExtensionItem }

        for item in items {
            guard let providers = item.attachments else { continue }

            for provider in providers {
                let type: UTType
                if provider.hasItemConformingToTypeIdentifier(UTType.spreadsheet.identifier) {
                    type = .spreadsheet
                } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    type = .pdf
                } else {
                    continue
                }

                provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, error in
                    guard let self, let url, error == nil else {
                        DispatchQueue.main.async { self?.finish() }
                        return
                    }

                    do {
                        let fm = FileManager.default
                        guard let container = fm.containerURL(
                            forSecurityApplicationGroupIdentifier: self.appGroup
                        ) else {
                            DispatchQueue.main.async { self.finish() }
                            return
                        }

                        let folder = container.appendingPathComponent("IncomingCompanyFile", isDirectory: true)
                        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

                        // Elimina SEMPRE il file precedente. Non deve mai riapparire
                        // un vecchio PDF quando viene condiviso un nuovo Excel.
                        if let old = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                            for file in old {
                                try? fm.removeItem(at: file)
                            }
                        }

                        let originalName = url.lastPathComponent
                        let destination = folder.appendingPathComponent(originalName)

                        try fm.copyItem(at: url, to: destination)

                        let defaults = UserDefaults(suiteName: self.appGroup)
                        defaults?.set(originalName, forKey: "incomingCompanyFilename")
                        defaults?.set(destination.path, forKey: "incomingCompanyPath")
                        defaults?.set(type == .spreadsheet ? "xlsx" : "pdf", forKey: "incomingCompanyType")
                        defaults?.set(Date().timeIntervalSince1970, forKey: "incomingCompanyTimestamp")
                        defaults?.synchronize()

                        DispatchQueue.main.async {
                            self.finish()
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.finish()
                        }
                    }
                }
                return
            }
        }

        finish()
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
