import Foundation

/// Thin OpenAI Chat Completions client for end-of-meeting notes.
final class OpenAIClient {
    enum ClientError: LocalizedError {
        case missingKey
        case emptyTranscript
        case badStatus(Int, String)
        case noContent

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Set your OpenAI API key first"
            case .emptyTranscript: return "No transcript to summarize"
            case .badStatus(let code, let body): return "OpenAI HTTP \(code): \(body)"
            case .noContent: return "OpenAI returned an empty summary"
            }
        }
    }

    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model
    }

    func summarizeMeeting(transcript: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ClientError.missingKey }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClientError.emptyTranscript }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You write concise meeting notes from a dual-channel transcript.
                    "Us" is the local participant (microphone). "Them" is remote/system audio.
                    Return markdown with:
                    ## Summary
                    ## Key points
                    ## Decisions
                    ## Action items
                    Keep it short. If a section has nothing, write "None noted."
                    """
                ],
                [
                    "role": "user",
                    "content": "Transcript:\n\n\(trimmed)"
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.badStatus(status, String(text.prefix(400)))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.noContent
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
