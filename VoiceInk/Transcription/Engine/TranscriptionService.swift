import Foundation

enum TranscriptionPromptSettings {
    static let userDefaultsKey = "TranscriptionPrompt"
    static let customLanguagePromptsKey = "CustomLanguagePrompts"

    static func currentPrompt(in defaults: UserDefaults = .standard) -> String? {
        let prompt = defaults.string(forKey: userDefaultsKey) ?? ""
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : prompt
    }

    static func saveCustomPrompt(_ prompt: String, for language: String, in defaults: UserDefaults = .standard) {
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLanguage.isEmpty else { return }

        var customPrompts = defaults.dictionary(forKey: customLanguagePromptsKey) as? [String: String] ?? [:]
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPrompt.isEmpty {
            customPrompts.removeValue(forKey: trimmedLanguage)
        } else {
            customPrompts[trimmedLanguage] = prompt
        }

        defaults.set(customPrompts, forKey: customLanguagePromptsKey)
        defaults.set(prompt, forKey: userDefaultsKey)
        defaults.synchronize()
        NotificationCenter.default.post(name: .promptDidChange, object: nil)
    }
}

struct TranscriptionRequestContext {
    let language: String?
    let prompt: String?

    static var currentDefaults: TranscriptionRequestContext {
        TranscriptionRequestContext(
            language: UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto",
            prompt: TranscriptionPromptSettings.currentPrompt()
        )
    }

    func scoped(to model: any TranscriptionModel) -> TranscriptionRequestContext {
        return self
    }
}

enum TranscriptionRequestTimeout {
    static let userDefaultsKey = "TranscriptionTimeoutSeconds"
    static let defaultSeconds = 300
    static let minimumSeconds = 30
    static let maximumSeconds = 1_200

    static func seconds(in defaults: UserDefaults = .standard) -> Int {
        sanitize(defaults.integer(forKey: userDefaultsKey))
    }

    static func interval(in defaults: UserDefaults = .standard) -> TimeInterval {
        TimeInterval(seconds(in: defaults))
    }

    static func sanitize(_ seconds: Int) -> Int {
        guard seconds > 0 else { return defaultSeconds }
        return min(max(seconds, minimumSeconds), maximumSeconds)
    }
}

/// A protocol defining the interface for a transcription service.
/// This allows for a unified way to handle both local and cloud-based transcription models.
protocol TranscriptionService {
    /// Transcribes the audio from a given file URL.
    ///
    /// - Parameters:
    ///   - audioURL: The URL of the audio file to transcribe.
    ///   - model: The `TranscriptionModel` to use for transcription. This provides context about the provider (local, OpenAI, etc.).
    /// - Returns: The transcribed text as a `String`.
    /// - Throws: An error if the transcription fails.
    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws -> String
}

extension TranscriptionService {
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let context = TranscriptionRequestContext.currentDefaults.scoped(to: model)
        return try await transcribe(audioURL: audioURL, model: model, context: context)
    }
}
