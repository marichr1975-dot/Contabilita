import SwiftUI
import UIKit
import Vision

struct BollettaOCRResult {
    let date: Date?
    let quantities: [String: Int]
}

struct BollettaScannerView: UIViewControllerRepresentable {
    let articleNames: [String]
    let completion: (BollettaOCRResult) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeCoordinator() -> Coordinator {
        Coordinator(articleNames: articleNames, completion: completion, dismiss: { self.presentationMode.wrappedValue.dismiss() })
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
        let dismiss: () -> Void

        init(articleNames: [String], completion: @escaping (BollettaOCRResult) -> Void, dismiss: @escaping () -> Void) {
            self.articleNames = articleNames
            self.completion = completion
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            guard let image = info[.originalImage] as? UIImage, let cgImage = image.cgImage else {
                dismiss()
                return
            }

            let articleNames = self.articleNames
            let completion = self.completion
            let dismiss = self.dismiss
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let result = Self.parse(observations, articleNames: articleNames)
                DispatchQueue.main.async {
                    completion(result)
                    dismiss()
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["it-IT", "en-US"]

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                    try handler.perform([request])
                } catch {
                    DispatchQueue.main.async {
                        completion(BollettaOCRResult(date: nil, quantities: [:]))
                        dismiss()
                    }
                }
            }
        }

        private struct OCRLine {
            let text: String
            let box: CGRect
        }

        private static func parse(_ observations: [VNRecognizedTextObservation], articleNames: [String]) -> BollettaOCRResult {
            let lines = observations.compactMap { obs -> OCRLine? in
                guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { return nil }
                return OCRLine(text: text, box: obs.boundingBox)
            }

            let date = extractDate(from: lines.map(\.text))
            let quantities = extractQuantities(from: lines, names: articleNames)
            return BollettaOCRResult(date: date, quantities: quantities)
        }

        private static func extractDate(from texts: [String]) -> Date? {
            let pattern = #"(?<!\d)(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})(?!\d)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let calendar = Calendar(identifier: .gregorian)
            for text in texts {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges == 4 else { continue }
                guard let day = Int((text as NSString).substring(with: match.range(at: 1))),
                      let month = Int((text as NSString).substring(with: match.range(at: 2))),
                      var year = Int((text as NSString).substring(with: match.range(at: 3))) else { continue }
                if year < 100 { year += 2000 }
                if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) { return date }
            }
            return nil
        }

        private static func extractQuantities(from lines: [OCRLine], names: [String]) -> [String: Int] {
            var result: [String: Int] = [:]

            for name in names {
                let normalizedName = normalize(name)
                let matches = lines.filter { line in
                    let n = normalize(line.text)
                    return n.contains(normalizedName) || fuzzyEnough(n, normalizedName)
                }
                guard let article = matches.max(by: { $0.box.width < $1.box.width }) else { continue }

                // Spesso la fotocamera riconosce articolo e quantità sulla stessa riga.
                if let sameLine = extractTrailingQuantity(from: article.text, articleName: name) {
                    result[name] = sameLine
                    continue
                }

                let candidates = lines.compactMap { line -> (Int, CGFloat)? in
                    let clean = line.text
                        .replacingOccurrences(of: ".", with: "")
                        .replacingOccurrences(of: ",", with: "")
                    let numbers = clean.split(whereSeparator: { !$0.isNumber })
                    guard let token = numbers.last, let value = Int(token), value >= 0, value <= 9999 else { return nil }
                    let yDistance = abs(line.box.midY - article.box.midY)
                    let isRight = line.box.minX > article.box.maxX - 0.02
                    guard yDistance < 0.045 && isRight else { return nil }
                    return (value, line.box.minX - article.box.maxX)
                }

                if let best = candidates.min(by: { $0.1 < $1.1 }) {
                    result[name] = best.0
                }
            }
            return result
        }

        private static func extractTrailingQuantity(from text: String, articleName: String) -> Int? {
            let nText = normalize(text)
            let nName = normalize(articleName)
            guard nText.contains(nName) else { return nil }
            let suffix = String(nText.dropFirst(nText.range(of: nName)?.upperBound.utf16Offset(in: nText) ?? nText.count))
            let digits = suffix.reversed().prefix(while: { $0.isNumber }).reversed()
            guard !digits.isEmpty, let value = Int(String(digits)), value >= 0, value <= 9999 else { return nil }
            return value
        }

        private static func standardArticleNames() -> [String] {
            [
                "GLAM", "GLAM XL", "ESSENTIAL", "CLOSE", "CASE", "TRAINING",
                "MESSENGER", "BAGPACK", "TODAY", "ACTIVITY", "ZAINI MARINA",
                "CLASSY", "ZAINO PRO", "case marina", "MONEYFUL", "BORSA IN STOFFA", "PORTAPC"
            ]
        }

        private static func normalize(_ text: String) -> String {
            text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .filter { $0.isLetter || $0.isNumber }
        }

        private static func fuzzyEnough(_ a: String, _ b: String) -> Bool {
            guard !a.isEmpty, !b.isEmpty else { return false }
            if a.count < 5 || b.count < 5 { return false }
            if abs(a.count - b.count) > 3 { return false }
            return levenshtein(a, b) <= 2
        }

        private static func levenshtein(_ a: String, _ b: String) -> Int {
            let a = Array(a), b = Array(b)
            var row = Array(0...b.count)
            for i in 1...a.count {
                var next = [i]
                for j in 1...b.count {
                    next.append(min(row[j] + 1, next[j - 1] + 1, row[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)))
                }
                row = next
            }
            return row[b.count]
        }
    }
}
