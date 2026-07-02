import Foundation

enum TranscriptionPromptSettings {
    static let userDefaultsKey = "TranscriptionPrompt"
    static let customLanguagePromptsKey = "CustomLanguagePrompts"
    static let defaultPrompt = "Transcribe the speech accurately. Preserve names, product terms, numbers, dates, emails, URLs, and formatting cues. Return only the transcribed text."
    private static let legacyDefaultPrompts: Set<String> = [
        "Hello, how are you doing? Nice to meet you.",
        "नमस्ते, कैसे हैं आप? आपसे मिलकर अच्छा लगा।",
        "নমস্কার, কেমন আছেন? আপনার সাথে দেখা হয়ে ভালো লাগলো।",
        "こんにちは、お元気ですか？お会いできて嬉しいです。",
        "안녕하세요, 잘 지내시나요? 만나서 반갑습니다.",
        "你好，最近好吗？见到你很高兴。",
        "สวัสดีครับ/ค่ะ, สบายดีไหม? ยินดีที่ได้พบคุณ",
        "Xin chào, bạn khỏe không? Rất vui được gặp bạn.",
        "你好，最近點呀？見到你好開心。",
        "¡Hola, ¿cómo estás? Encantado de conocerte.",
        "Bonjour, comment allez-vous? Ravi de vous rencontrer.",
        "Hallo, wie geht es dir? Schön dich kennenzulernen.",
        "Ciao, come stai? Piacere di conoscerti.",
        "Olá, como você está? Prazer em conhecê-lo.",
        "Здравствуйте, как ваши дела? Приятно познакомиться.",
        "Cześć, jak się masz? Miło cię poznać.",
        "Hallo, hoe gaat het? Aangenaam kennis te maken.",
        "Merhaba, nasılsın? Tanıştığımıza memnun oldum.",
        "مرحباً، كيف حالك؟ سعيد بلقائك.",
        "سلام، حال شما چطور است؟ از آشنایی با شما خوشوقتم.",
        ",שלום, מה שלומך? נעים להכיר",
        "வணக்கம், எப்படி இருக்கிறீர்கள்? உங்களை சந்தித்ததில் மகிழ்ச்சி.",
        "నమస్కారం, ఎలా ఉన్నారు? కలవడం చాలా సంతోషం.",
        "നമസ്കാരം, സുഖമാണോ? കണ്ടതിൽ സന്തോഷം.",
        "ನಮಸ್ಕಾರ, ಹೇಗಿದ್ದೀರಾ? ನಿಮ್ಮನ್ನು ಭೇಟಿಯಾಗಿ ಸಂತೋಷವಾಗಿದೆ.",
        "السلام علیکم، کیسے ہیں آپ؟ آپ سے مل کر خوشی ہوئی۔"
    ]

    static func currentPrompt(in defaults: UserDefaults = .standard) -> String {
        let prompt = defaults.string(forKey: userDefaultsKey) ?? ""
        return promptOrDefault(prompt)
    }

    static func promptOrDefault(_ prompt: String?) -> String {
        guard let prompt else { return defaultPrompt }
        return isDefaultSelection(prompt) ? defaultPrompt : prompt
    }

    static func saveCustomPrompt(_ prompt: String, for language: String, in defaults: UserDefaults = .standard) {
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLanguage.isEmpty else { return }

        var customPrompts = defaults.dictionary(forKey: customLanguagePromptsKey) as? [String: String] ?? [:]
        if isDefaultSelection(prompt) {
            customPrompts.removeValue(forKey: trimmedLanguage)
            defaults.set("", forKey: userDefaultsKey)
        } else {
            customPrompts[trimmedLanguage] = prompt
            defaults.set(prompt, forKey: userDefaultsKey)
        }

        defaults.set(customPrompts, forKey: customLanguagePromptsKey)
        defaults.synchronize()
        NotificationCenter.default.post(name: .promptDidChange, object: nil)
    }

    static func isDefaultSelection(_ prompt: String) -> Bool {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrompt.isEmpty || trimmedPrompt == defaultPrompt || legacyDefaultPrompts.contains(trimmedPrompt)
    }
}

struct TranscriptionRequestContext {
    let language: String?
    let prompt: String?

    var effectivePrompt: String {
        TranscriptionPromptSettings.promptOrDefault(prompt)
    }

    static var currentDefaults: TranscriptionRequestContext {
        TranscriptionRequestContext(
            language: UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto",
            prompt: TranscriptionPromptSettings.currentPrompt()
        )
    }

    func scoped(to model: any TranscriptionModel) -> TranscriptionRequestContext {
        if let customModel = model as? CustomCloudModel,
           let modelPrompt = customModel.transcriptionPrompt,
           !TranscriptionPromptSettings.isDefaultSelection(modelPrompt) {
            return TranscriptionRequestContext(language: language, prompt: modelPrompt)
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
