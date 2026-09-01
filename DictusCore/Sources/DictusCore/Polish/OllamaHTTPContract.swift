import Foundation

/// Small, provider-neutral contract for Ollama's OpenAI-compatible endpoint.
/// The app owns URLSession and prompt construction; this type keeps wire parsing
/// deterministic and testable without requiring an Ollama process.
public enum OllamaHTTPContract {
    public enum Error: Swift.Error, Equatable, Sendable {
        case httpStatus(Int, String)
        case malformedResponse
    }

    public static func endpoint(baseURL: String) -> URL? {
        guard var url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            url.appendPathComponent("v1")
        } else if path != "v1" && !path.hasSuffix("/v1") {
            url.appendPathComponent("v1")
        }
        return url.appendingPathComponent("chat").appendingPathComponent("completions")
    }

    public static func responseText(data: Data, statusCode: Int) throws -> String {
        guard (200..<300).contains(statusCode) else {
            throw Error.httpStatus(statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.malformedResponse
        }
        return content
    }
}
