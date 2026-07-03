import Foundation

enum EnhancementPromptStore {
    static let userDefaultsKey = "customPrompts"

    static func loadPrompts(from defaults: UserDefaults = .standard) -> [CustomPrompt] {
        guard let savedPromptsData = defaults.data(forKey: userDefaultsKey),
              let decodedPrompts = try? JSONDecoder().decode([CustomPrompt].self, from: savedPromptsData) else {
            return PromptTemplates.seedPrompts
        }

        return decodedPrompts
    }

    static func savePrompts(_ prompts: [CustomPrompt], to defaults: UserDefaults = .standard) {
        guard let encoded = try? JSONEncoder().encode(prompts) else { return }
        defaults.set(encoded, forKey: userDefaultsKey)
    }
}
