import Foundation


@MainActor
class WhisperPrompt: ObservableObject {
    @Published var transcriptionPrompt: String = TranscriptionPromptSettings.currentPrompt()
    
    // Store user-customized prompts
    private var customPrompts: [String: String] = [:]
    
    init() {
        loadCustomPrompts()
        updateTranscriptionPrompt()
        
        // Setup notification observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: .languageDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleLanguageChange() {
        updateTranscriptionPrompt()
    }
    
    private func loadCustomPrompts() {
        if let savedPrompts = UserDefaults.standard.dictionary(forKey: TranscriptionPromptSettings.customLanguagePromptsKey) as? [String: String] {
            customPrompts = savedPrompts
        }
    }
    
    private func saveCustomPrompts() {
        UserDefaults.standard.set(customPrompts, forKey: TranscriptionPromptSettings.customLanguagePromptsKey)
        UserDefaults.standard.synchronize() // Force immediate synchronization
    }
    
    func updateTranscriptionPrompt() {
        loadCustomPrompts()

        // Get the currently selected language from UserDefaults
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
        
        // Get the prompt for the selected language (custom if available, otherwise the shared default preset)
        let prompt = getLanguagePrompt(for: selectedLanguage)
        
        transcriptionPrompt = prompt
        TranscriptionPromptSettings.saveCustomPrompt(prompt, for: selectedLanguage)
    }
    
    func getLanguagePrompt(for language: String) -> String {
        // First check if there's a custom prompt for this language
        if let customPrompt = customPrompts[language],
           !TranscriptionPromptSettings.isDefaultSelection(customPrompt) {
            return customPrompt
        }
        
        // Otherwise return the shared default preset.
        return TranscriptionPromptSettings.defaultPrompt
    }
    
    func setCustomPrompt(_ prompt: String, for language: String) {
        customPrompts[language] = prompt
        saveCustomPrompts()
        updateTranscriptionPrompt()
        
        // Force update the UI
        objectWillChange.send()
    }
}
