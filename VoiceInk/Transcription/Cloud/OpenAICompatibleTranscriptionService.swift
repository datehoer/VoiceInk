import Foundation

class OpenAICompatibleTranscriptionService {
    func transcribe(audioURL: URL, model: CustomCloudModel, context: TranscriptionRequestContext, timeout: TimeInterval = TranscriptionRequestTimeout.interval()) async throws -> String {
        guard let url = URL(string: model.apiEndpoint) else {
            throw NSError(domain: "CustomWhisperTranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API endpoint URL"])
        }

        let audioData = try Self.loadAudioData(from: audioURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(model.apiKey)", forHTTPHeaderField: "Authorization")
        let session = Self.makeURLSession(timeout: timeout)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse

        switch model.requestMode {
        case .chatCompletions:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.makeChatCompletionsRequestBody(
                audioData: audioData,
                modelName: model.modelName,
                context: context,
                audioFormat: Self.audioFormat(for: audioURL)
            )
            (data, response) = try await session.data(for: request)
        case .customJSON:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            guard let template = model.customBodyTemplate, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CloudTranscriptionError.dataEncodingError
            }
            request.httpBody = try Self.makeCustomJSONRequestBody(
                audioData: audioData,
                modelName: model.modelName,
                context: context,
                audioFormat: Self.audioFormat(for: audioURL),
                template: template
            )
            (data, response) = try await session.data(for: request)
        case .audioTranscriptions:
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let body = Self.makeAudioTranscriptionsRequestBody(
                audioData: audioData,
                fileName: audioURL.lastPathComponent,
                modelName: model.modelName,
                boundary: boundary,
                context: context
            )
            (data, response) = try await session.upload(for: request, from: body)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        do {
            let text = try Self.decodeTranscriptionText(from: data, requestMode: model.requestMode)
            guard !text.isEmpty else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }

    static func makeChatCompletionsRequestBody(audioData: Data, modelName: String, context: TranscriptionRequestContext, audioFormat: String) throws -> Data {
        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": chatTranscriptionInstruction(context: context)
                        ],
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": audioData.base64EncodedString(),
                                "format": audioFormat
                            ]
                        ]
                    ]
                ]
            ],
            "temperature": 0.0,
            "stream": false
        ]

        guard JSONSerialization.isValidJSONObject(body) else {
            throw CloudTranscriptionError.dataEncodingError
        }

        return try JSONSerialization.data(withJSONObject: body)
    }

    static func makeCustomJSONRequestBody(audioData: Data, modelName: String, context: TranscriptionRequestContext, audioFormat: String, template: String) throws -> Data {
        let selectedLanguage = context.language ?? "auto"
        let prompt = context.prompt ?? ""
        let replacements = [
            "{{model}}": modelName,
            "{{prompt}}": prompt,
            "{{language}}": selectedLanguage,
            "{{audio_base64}}": audioData.base64EncodedString(),
            "{{audio_format}}": audioFormat,
            "{{temperature}}": "0"
        ]

        var renderedTemplate = template
        for (placeholder, value) in replacements {
            if placeholder == "{{temperature}}" {
                renderedTemplate = renderedTemplate.replacingOccurrences(of: placeholder, with: value)
            } else {
                renderedTemplate = renderedTemplate.replacingOccurrences(of: placeholder, with: try escapedJSONStringContent(value))
            }
        }

        guard let data = renderedTemplate.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(jsonObject) else {
            throw CloudTranscriptionError.dataEncodingError
        }

        return try JSONSerialization.data(withJSONObject: jsonObject)
    }

    private static func makeAudioTranscriptionsRequestBody(audioData: Data, fileName: String, modelName: String, boundary: String, context: TranscriptionRequestContext) -> Data {
        let selectedLanguage = context.language ?? "auto"
        let crlf = "\r\n"
        var body = Data()

        func append(_ string: String) { body.append(string.data(using: .utf8)!) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\(crlf)")
            append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)")
            body.append(value.data(using: .utf8)!)
            append(crlf)
        }

        append("--\(boundary)\(crlf)")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\(crlf)")
        append("Content-Type: audio/wav\(crlf)\(crlf)")
        body.append(audioData)
        append(crlf)

        field("model", modelName)
        field("response_format", "json")
        field("temperature", "0")

        if selectedLanguage != "auto" && !selectedLanguage.isEmpty {
            field("language", selectedLanguage)
        }

        append("--\(boundary)--\(crlf)")
        return body
    }

    private static func loadAudioData(from audioURL: URL) throws -> Data {
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        return audioData
    }

    private static func makeURLSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private static func audioFormat(for audioURL: URL) -> String {
        audioURL.pathExtension.lowercased() == "mp3" ? "mp3" : "wav"
    }

    private static func chatTranscriptionInstruction(context: TranscriptionRequestContext) -> String {
        var instruction = "Transcribe this audio. Return only the transcribed text."
        let selectedLanguage = context.language ?? "auto"
        if selectedLanguage != "auto" && !selectedLanguage.isEmpty {
            instruction += "\nAudio language: \(selectedLanguage)."
        }
        if let prompt = context.prompt, !prompt.isEmpty {
            instruction += "\nUse this transcription prompt/context as guidance: \(prompt)"
        }
        return instruction
    }

    static func decodeTranscriptionText(from data: Data, requestMode: CustomTranscriptionRequestMode) throws -> String {
        switch requestMode {
        case .chatCompletions:
            return try JSONDecoder()
                .decode(ChatCompletionsResponse.self, from: data)
                .choices
                .first?
                .message
                .content
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .audioTranscriptions:
            return try JSONDecoder()
                .decode(TranscriptionResponse.self, from: data)
                .text
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .customJSON:
            return try decodeFlexibleTranscriptionText(from: data)
        }
    }

    private static func decodeFlexibleTranscriptionText(from data: Data) throws -> String {
        if let transcriptionResponse = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) {
            let trimmedText = transcriptionResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                return trimmedText
            }
        }

        if let chatResponse = try? JSONDecoder().decode(ChatCompletionsResponse.self, from: data),
           let content = chatResponse.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return content
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudTranscriptionError.noTranscriptionReturned
        }

        for key in ["transcription", "result", "output_text"] {
            if let text = object[key] as? String {
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    return trimmedText
                }
            }
        }

        return ""
    }

    private static func escapedJSONStringContent(_ value: String) throws -> String {
        let encodedData = try JSONEncoder().encode(value)
        guard let encodedString = String(data: encodedData, encoding: .utf8),
              encodedString.count >= 2 else {
            throw CloudTranscriptionError.dataEncodingError
        }
        return String(encodedString.dropFirst().dropLast())
    }

    private struct TranscriptionResponse: Decodable {
        let text: String
        let language: String?
        let duration: Double?
    }

    private struct ChatCompletionsResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String
        }
    }
}
