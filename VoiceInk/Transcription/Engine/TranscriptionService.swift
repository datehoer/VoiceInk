import Foundation

struct TranscriptionRequestContext {
    let language: String?
    let prompt: String?

    static var currentDefaults: TranscriptionRequestContext {
        TranscriptionRequestContext(
            language: UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto",
            prompt: UserDefaults.standard.string(forKey: "TranscriptionPrompt")
        )
    }

    func scoped(to model: any TranscriptionModel) -> TranscriptionRequestContext {
        guard model.provider == .whisper else {
            return TranscriptionRequestContext(language: language, prompt: nil)
        }

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
