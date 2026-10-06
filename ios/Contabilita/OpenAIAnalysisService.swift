import Foundation

struct OpenAIAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class OpenAIAnalysisService {
    static let shared = OpenAIAnalysisService()
    private let baseURL = URL(string: "https://api.openai.com/v1")!

    private init() {}

    func uploadFile(url: URL, apiKey: String) async throws -> String {
        let data = try Data(contentsOf: url)
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        let mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"purpose\"\r\n\r\nuser_data\r\n".utf8))
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mime)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: baseURL.appendingPathComponent("files"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: responseData)

        let decoded = try JSONDecoder().decode(OpenAIFileResponse.self, from: responseData)
        return decoded.id
    }

    func respond(
        apiKey: String,
        prompt: String,
        fileIDs: [String],
        previousResponseID: String? = nil
    ) async throws -> (id: String, text: String) {
        var content: [[String: Any]] = [[
            "type": "input_text",
            "text": prompt
        ]]

        for id in fileIDs {
            content.append([
                "type": "input_file",
                "file_id": id
            ])
        }

        var payload: [String: Any] = [
            "model": "gpt-5.4",
            "input": [[
                "role": "user",
                "content": content
            ]]
        ]

        if let previousResponseID {
            payload["previous_response_id"] = previousResponseID
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: baseURL.appendingPathComponent("responses"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: responseData)

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: responseData)
        let text = decoded.outputText ?? extractOutputText(from: responseData) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIAPIError(message: "ChatGPT ha restituito una risposta vuota.")
        }
        return (decoded.id, text)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let serverMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String }
            throw OpenAIAPIError(message: serverMessage ?? "Errore OpenAI. Codice HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
    }

    private func extractOutputText(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = root["output"] as? [[String: Any]] else { return nil }
        var pieces: [String] = []
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if let text = part["text"] as? String { pieces.append(text) }
            }
        }
        return pieces.joined(separator: "\n")
    }
}

private struct OpenAIFileResponse: Decodable {
    let id: String
}

private struct OpenAIResponse: Decodable {
    let id: String
    let outputText: String?

    enum CodingKeys: String, CodingKey {
        case id
        case outputText = "output_text"
    }
}
