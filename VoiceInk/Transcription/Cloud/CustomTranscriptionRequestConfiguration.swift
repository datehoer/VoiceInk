import Foundation

enum CustomTranscriptionRequestMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case audioTranscriptions
    case chatCompletions
    case customJSON

    var id: String { rawValue }

    var title: String {
        switch self {
        case .audioTranscriptions:
            return "Audio"
        case .chatCompletions:
            return "Chat"
        case .customJSON:
            return "Custom JSON"
        }
    }

    var detailTitle: String {
        switch self {
        case .audioTranscriptions:
            return "Audio Transcriptions"
        case .chatCompletions:
            return "Chat Completions Audio"
        case .customJSON:
            return "Custom JSON Template"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .audioTranscriptions:
            return "https://api.openai.com/v1/audio/transcriptions"
        case .chatCompletions, .customJSON:
            return "https://api.openai.com/v1/chat/completions"
        }
    }

    static func inferred(from endpoint: String) -> CustomTranscriptionRequestMode {
        let lowercasedEndpoint = endpoint.lowercased()
        if lowercasedEndpoint.contains("chat/completions") {
            return .chatCompletions
        }
        return .audioTranscriptions
    }
}

enum CustomTranscriptionBodyTemplatePresets {
    static let chatAudioJSON = """
    {
      "model": "{{model}}",
      "messages": [
        {
          "role": "user",
          "content": [
            { "type": "text", "text": "Transcribe this audio. Return only the transcribed text. Prompt: {{prompt}} Language: {{language}}" },
            { "type": "input_audio", "input_audio": { "data": "{{audio_base64}}", "format": "{{audio_format}}" } }
          ]
        }
      ],
      "temperature": {{temperature}},
      "stream": false
    }
    """

    static let simpleInputAudioJSON = """
    {
      "model": "{{model}}",
      "input": [
        {
          "role": "user",
          "content": [
            { "type": "input_text", "text": "{{prompt}}" },
            { "type": "input_audio", "input_audio": { "data": "{{audio_base64}}", "format": "{{audio_format}}" } }
          ]
        }
      ],
      "temperature": {{temperature}}
    }
    """

    static let placeholderTokens = [
        "{{model}}",
        "{{prompt}}",
        "{{language}}",
        "{{audio_base64}}",
        "{{audio_format}}",
        "{{temperature}}"
    ]
}

enum CustomModelDiscoveryEndpointResolver {
    static func endpoint(from apiEndpoint: String) -> URL? {
        let trimmedEndpoint = apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedEndpoint),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }

        components.query = nil
        components.fragment = nil

        var pathComponents = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        let lowercasedComponents = pathComponents.map { $0.lowercased() }
        if lowercasedComponents.last == "models" {
            return components.url
        }

        if lowercasedComponents.suffix(2) == ["audio", "transcriptions"] ||
            lowercasedComponents.suffix(2) == ["chat", "completions"] {
            pathComponents.removeLast(2)
        } else if lowercasedComponents.last == "transcriptions" || lowercasedComponents.last == "completions" {
            pathComponents.removeLast()
        }

        pathComponents.append("models")
        components.path = "/" + pathComponents.joined(separator: "/")
        return components.url
    }
}

enum CustomModelDiscoveryResponseParser {
    static func modelNames(from data: Data) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data)
        var names: [String] = []

        func appendUnique(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !names.contains(trimmed) else { return }
            names.append(trimmed)
        }

        func collect(from array: [Any]) {
            for item in array {
                if let string = item as? String {
                    appendUnique(string)
                } else if let dictionary = item as? [String: Any] {
                    appendUnique(dictionary["id"] as? String)
                    appendUnique(dictionary["name"] as? String)
                }
            }
        }

        if let dictionary = object as? [String: Any] {
            if let data = dictionary["data"] as? [Any] {
                collect(from: data)
            }
            if let models = dictionary["models"] as? [Any] {
                collect(from: models)
            }
        } else if let array = object as? [Any] {
            collect(from: array)
        }

        return names
    }
}

enum CustomModelDiscoveryError: LocalizedError {
    case invalidEndpoint
    case requestFailed(statusCode: Int, message: String)
    case noModelsReturned

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return String(localized: "Models endpoint must be a valid URL")
        case .requestFailed(let statusCode, let message):
            return String(format: String(localized: "Models request failed with status code %lld: %@"), Int64(statusCode), message)
        case .noModelsReturned:
            return String(localized: "No models were returned")
        }
    }
}

final class CustomModelDiscoveryService {
    func fetchModels(endpoint: URL, apiKey: String, timeout: TimeInterval = 30) async throws -> [String] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No error message"
            throw CustomModelDiscoveryError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        let names = try CustomModelDiscoveryResponseParser.modelNames(from: data)
        guard !names.isEmpty else {
            throw CustomModelDiscoveryError.noModelsReturned
        }
        return names
    }
}
