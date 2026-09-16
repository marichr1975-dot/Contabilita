import Foundation
import UniformTypeIdentifiers

struct CompanyFile {
    let url: URL
    let name: String
    let type: CompanyFileType
    let importedAt: Date
}

enum CompanyFileType {
    case excel
    case pdf
    case unknown
}

final class PDFTransfer {

    static let appGroup = "group.com.gotrail.contabilita"
    static let folderName = "IncomingCompanyFile"

    private static var folderURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        )?.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Restituisce esclusivamente il file ricevuto dall'ultima condivisione.
    /// Non usa più vecchi PDF presenti in cache o chiavi legacy.
    static func latestCompanyFile() -> CompanyFile? {
        guard let folder = folderURL else { return nil }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let valid = files.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "xlsx" || ext == "xls" || ext == "pdf"
        }

        guard let file = valid.max(by: {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d1 < d2
        }) else {
            return nil
        }

        let ext = file.pathExtension.lowercased()
        let type: CompanyFileType = ext == "xlsx" || ext == "xls" ? .excel : (ext == "pdf" ? .pdf : .unknown)

        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        return CompanyFile(url: file, name: file.lastPathComponent, type: type, importedAt: date)
    }

    static func consumeIncomingFile() -> CompanyFile? {
        guard let file = latestCompanyFile() else { return nil }

        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.removeObject(forKey: "incomingCompanyFilename")
        defaults?.removeObject(forKey: "incomingCompanyPath")
        defaults?.removeObject(forKey: "incomingCompanyType")
        defaults?.removeObject(forKey: "incomingCompanyTimestamp")
        defaults?.synchronize()

        return file
    }

    static func isExcel(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "xlsx" || ext == "xls" { return true }
        if let type = UTType(filenameExtension: ext) {
            return type.conforms(to: .spreadsheet)
        }
        return false
    }

    static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }
}
