import Foundation
import LLMkit

enum CustomEnhancementRequestMode: String, Hashable, CaseIterable, Identifiable {
    case chatCompletions
    case customJSON

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatCompletions:
            return "Chat"
        case .customJSON:
            return "Custom JSON"
        }
    }
}

enum CustomEnhancementBodyTemplatePresets {
    static let chatCompletionsJSON = """
    {
      "model": "{{model}}",
      "messages": {{messages_json}},
      "temperature": {{temperature}},
      "stream": false
    }
    """

    static let explicitSystemUserJSON = """
    {
      "model": "{{model}}",
      "messages": [
        { "role": "system", "content": "{{system_prompt}}" },
        { "role": "user", "content": "{{user_message}}" }
      ],
      "temperature": {{temperature}},
      "stream": false
    }
    """

    static let placeholderTokens = [
        "{{model}}",
        "{{system_prompt}}",
        "{{user_message}}",
        "{{messages_json}}",
        "{{temperature}}"
    ]
}

enum CustomEnhancementRequestTemplateRenderer {
    static func makeRequestBody(
        modelName: String,
        systemPrompt: String?,
        userMessage: String,
        temperature: Double,
        template: String
    ) throws -> Data {
        try makeRequestBody(
            modelName: modelName,
            messages: [.user(userMessage)],
            systemPrompt: systemPrompt,
            temperature: temperature,
            template: template
        )
    }

    static func makeRequestBody(
        modelName: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        temperature: Double,
        template: String
    ) throws -> Data {
        let allMessages = chatMessages(messages: messages, systemPrompt: systemPrompt)
        let userMessage = messages.first(where: { $0.role == "user" })?.content ?? ""
        let replacements: [String: ReplacementValue] = [
            "{{model}}": .string(modelName),
            "{{system_prompt}}": .string(systemPrompt ?? ""),
            "{{user_message}}": .string(userMessage),
            "{{messages_json}}": .raw(try jsonString(from: allMessages.map { ["role": $0.role, "content": $0.content] })),
            "{{temperature}}": .raw(Self.temperatureString(temperature))
        ]

        var renderedTemplate = template
        for (placeholder, value) in replacements {
            switch value {
            case .raw(let rawValue):
                renderedTemplate = renderedTemplate.replacingOccurrences(of: placeholder, with: rawValue)
            case .string(let stringValue):
                renderedTemplate = renderedTemplate.replacingOccurrences(
                    of: placeholder,
                    with: try escapedJSONStringContent(stringValue)
                )
            }
        }

        guard let data = renderedTemplate.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(jsonObject) else {
            throw LLMKitError.encodingError
        }

        return try JSONSerialization.data(withJSONObject: jsonObject)
    }

    private static func chatMessages(messages: [ChatMessage], systemPrompt: String?) -> [ChatMessage] {
        var allMessages = messages
        if let systemPrompt, !systemPrompt.isEmpty {
            allMessages.insert(.system(systemPrompt), at: 0)
        }
        return allMessages
    }

    private static func jsonString(from object: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw LLMKitError.encodingError
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw LLMKitError.encodingError
        }
        return string
    }

    private static func escapedJSONStringContent(_ value: String) throws -> String {
        let encodedData = try JSONEncoder().encode(value)
        guard let encodedString = String(data: encodedData, encoding: .utf8),
              encodedString.count >= 2 else {
            throw LLMKitError.encodingError
        }
        return String(encodedString.dropFirst().dropLast())
    }

    private static func temperatureString(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private enum ReplacementValue {
        case raw(String)
        case string(String)
    }
}

enum CustomEnhancementRequestExecutor {
    static func verifyAPIKey(
        baseURL: URL,
        apiKey: String,
        modelName: String,
        bodyTemplate: String?,
        timeout: TimeInterval = 10
    ) async -> (isValid: Bool, errorMessage: String?) {
        let trimmedTemplate = bodyTemplate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedTemplate.isEmpty else {
            return await OpenAILLMClient.verifyAPIKey(
                baseURL: baseURL,
                apiKey: apiKey,
                model: modelName,
                timeout: timeout
            )
        }

        let body: Data
        do {
            body = try CustomEnhancementRequestTemplateRenderer.makeRequestBody(
                modelName: modelName,
                systemPrompt: nil,
                userMessage: "test",
                temperature: 0.3,
                template: trimmedTemplate
            )
        } catch {
            return (false, "Custom JSON template must be valid JSON")
        }

        do {
            let (data, http) = try await sendJSONRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                body: body,
                timeout: timeout
            )

            guard (200...299).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                return (false, message)
            }

            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    static func chatCompletion(baseURL: URL, apiKey: String, body: Data, timeout: TimeInterval) async throws -> String {
        let (data, http) = try await sendJSONRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            body: body,
            timeout: timeout
        )

        guard (200...299).contains(http.statusCode) else {
            throw LLMKitError.httpError(
                statusCode: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? ""
            )
        }

        let text = try decodeResponseText(from: data)
        guard !text.isEmpty else {
            throw LLMKitError.noResultReturned
        }
        return text
    }

    private static func sendJSONRequest(baseURL: URL, apiKey: String, body: Data, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMKitError.missingAPIKey
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMKitError.networkError("No HTTP response received.")
            }
            return (data, http)
        } catch let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut {
            throw LLMKitError.timeout
        } catch {
            throw LLMKitError.networkError(error.localizedDescription)
        }
    }

    private static func decodeResponseText(from data: Data) throws -> String {
        if let response = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
           let content = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return content
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMKitError.decodingError("Expected JSON object response.")
        }

        for key in ["text", "result", "output_text"] {
            if let text = object[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return ""
    }

    private struct OpenAIChatResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String
        }
    }
}
