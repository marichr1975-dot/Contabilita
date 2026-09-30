import SwiftUI
import UIKit
import Vision

struct BollettaOCRResult {
    let date: Date?
    let quantities: [String: Int]
    let rawText: String
}

struct BollettaScannerView: UIViewControllerRepresentable {
    let articleNames: [String]
    let completion: (BollettaOCRResult) -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(articleNames: articleNames, completion: completion, cancel: cancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let articleNames: [String]
        let completion: (BollettaOCRResult) -> Void
        let cancel: () -> Void

        init(articleNames: [String], completion: @escaping (BollettaOCRResult) -> Void, cancel: @escaping () -> Void) {
            self.articleNames = articleNames
            self.completion = completion
            self.cancel = cancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { cancel() }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            guard let image = info[.originalImage] as? UIImage, let cgImage = image.cgImage else { cancel(); return }
            let articleNames = self.articleNames
            let completion = self.completion
            let cancel = self.cancel
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let result = Self.parse(observations, articleNames: articleNames)
                DispatchQueue.main.async { completion(result) }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["it-IT", "en-US"]
            request.minimumTextHeight = 0.008

            let orientation = Self.cgOrientation(from: image.imageOrientation)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                    try handler.perform([request])
                } catch {
                    DispatchQueue.main.async {
                        completion(BollettaOCRResult(date: nil, quantities: [:], rawText: "ERRORE: impossibile leggere la foto."))
                        self.cancel()
                    }
                }
            }
        }

        private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
            switch orientation {
            case .up: return .up
            case .down: return .down
            case .left: return .left
            case .right: return .right
            case .upMirrored: return .upMirrored
            case .downMirrored: return .downMirrored
            case .leftMirrored: return .leftMirrored
            case .rightMirrored: return .rightMirrored
            @unknown default: return .up
            }
        }

        private struct OCRLine { let text: String; let box: CGRect }

        private static func parse(_ observations: [VNRecognizedTextObservation], articleNames: [String]) -> BollettaOCRResult {
            let lines = observations.compactMap { obs -> OCRLine? in
                guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { return nil }
                return OCRLine(text: text.trimmingCharacters(in: .whitespacesAndNewlines), box: obs.boundingBox)
            }
            let ordered = lines.sorted {
                if abs($0.box.midY - $1.box.midY) > 0.018 { return $0.box.midY > $1.box.midY }
                return $0.box.minX < $1.box.minX
            }
            let rawText = ordered.map(\.text).joined(separator: "\n")
            return BollettaOCRResult(date: extractDate(from: ordered), quantities: extractQuantities(from: ordered, names: articleNames), rawText: rawText)
        }

        private static func normalizedOCR(_ text: String) -> String {
            text
                .replacingOccurrences(of: "O", with: "0")
                .replacingOccurrences(of: "o", with: "0")
                .replacingOccurrences(of: "I", with: "1")
                .replacingOccurrences(of: "l", with: "1")
                .replacingOccurrences(of: "|", with: "1")
        }

        private static func extractDate(from lines: [OCRLine]) -> Date? {
            let calendar = Calendar(identifier: .gregorian)
            let patterns = [
                #"(?<!\d)(\d{1,2})\s*[./-]\s*(\d{1,2})\s*[./-]\s*(\d{2,4})(?!\d)"#,
                #"(?<!\d)(\d{1,2})\s+(\d{1,2})\s+(\d{4})(?!\d)"#
            ]

            // Prima cerca nelle singole righe OCR, poi nel testo completo: in
            // alcune foto Vision spezza la data in più frammenti.
            var testi = lines.map(\.text)
            testi.append(lines.map(\.text).joined(separator: " "))

            for original in testi {
                let text = normalizedOCR(original)
                    .replacingOccurrences(of: "—", with: "-")
                    .replacingOccurrences(of: "–", with: "-")
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                for pattern in patterns {
                    guard let regex = try? NSRegularExpression(pattern: pattern),
                          let m = regex.firstMatch(in: text, range: range),
                          m.numberOfRanges >= 4 else { continue }

                    let day = Int((text as NSString).substring(with: m.range(at: 1))) ?? 0
                    let month = Int((text as NSString).substring(with: m.range(at: 2))) ?? 0
                    var year = Int((text as NSString).substring(with: m.range(at: 3))) ?? 0
                    if year < 100 { year += 2000 }
                    guard (1...31).contains(day), (1...12).contains(month),
                          let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                          calendar.component(.day, from: date) == day,
                          calendar.component(.month, from: date) == month else { continue }
                    return date
                }
            }
            return nil
        }

        private static func extractQuantities(from lines: [OCRLine], names: [String]) -> [String: Int] {
            var result: [String: Int] = [:]

            for name in names {
                let normalizedName = normalize(name)
                guard !normalizedName.isEmpty else { continue }

                let matches = lines.enumerated().filter { item in
                    let normalizedLine = normalize(item.element.text)
                    return normalizedLine.contains(normalizedName) || fuzzyEnough(normalizedLine, normalizedName)
                }
                guard let (index, articleLine) = matches.first else { continue }

                // Caso più affidabile: articolo e quantità sulla stessa riga.
                if let value = quantityAfterArticle(in: articleLine.text, articleName: name) {
                    result[name] = value
                    continue
                }

                // Caso tipico di una tabella: il numero è nella stessa riga
                // oppure subito a destra dell'articolo.
                var candidates: [(value: Int, score: CGFloat)] = []
                for (j, line) in lines.enumerated() {
                    let dy = abs(line.box.midY - articleLine.box.midY)
                    guard dy < 0.085 else { continue }

                    for value in numbers(in: line.text) where value >= 0 && value <= 9999 {
                        if j == index {
                            // Se la riga contiene l'articolo, preferiamo il
                            // numero che compare dopo il nome.
                            let score = quantityAfterArticle(in: line.text, articleName: name) != nil ? 0 : 0.20
                            candidates.append((value, score))
                        } else {
                            let horizontalGap = line.box.minX - articleLine.box.maxX
                            let alignment = abs(line.box.midY - articleLine.box.midY)
                            let penalty = horizontalGap >= -0.03 ? 0 : 0.50
                            candidates.append((value, dy * 2 + alignment + penalty))
                        }
                    }
                }

                if let best = candidates.min(by: { $0.score < $1.score }) {
                    result[name] = best.value
                }
            }
            return result
        }

        private static func quantityAfterArticle(in text: String, articleName: String) -> Int? {
            let normalizedText = normalize(text)
            let normalizedName = normalize(articleName)
            guard let range = normalizedText.range(of: normalizedName) else { return nil }
            let suffix = String(normalizedText[range.upperBound...])
            let matches = numbers(in: suffix)
            return matches.first(where: { $0 >= 0 && $0 <= 9999 })
        }

        private static func numbers(in text: String) -> [Int] {
            let t = normalizedOCR(text)
                .replacingOccurrences(of: ",", with: " ")
                .replacingOccurrences(of: ".", with: " ")
            return t.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }

        private static func normalize(_ text: String) -> String {
            text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).filter { $0.isLetter || $0.isNumber }
        }

        private static func fuzzyEnough(_ a: String, _ b: String) -> Bool {
            guard a.count >= 5, b.count >= 5, abs(a.count - b.count) <= 3 else { return false }
            return levenshtein(a, b) <= 2
        }

        private static func levenshtein(_ a: String, _ b: String) -> Int {
            let a = Array(a), b = Array(b); var row = Array(0...b.count)
            for i in 1...a.count {
                var next = [i]
                for j in 1...b.count { next.append(min(row[j] + 1, next[j - 1] + 1, row[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))) }
                row = next
            }
            return row[b.count]
        }
    }
}
