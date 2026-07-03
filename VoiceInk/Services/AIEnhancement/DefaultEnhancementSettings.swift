import Foundation

enum DefaultEnhancementSettings {
    static let isEnabledKey = "DefaultAIEnhancementEnabled"
    static let providerKey = "DefaultAIEnhancementProvider"
    static let modelKey = "DefaultAIEnhancementModel"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: isEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: isEnabledKey)
    }

    static func configuredProviderName(in defaults: UserDefaults = .standard) -> String? {
        nonEmptyString(defaults.string(forKey: providerKey))
    }

    static func configuredModelName(in defaults: UserDefaults = .standard) -> String? {
        nonEmptyString(defaults.string(forKey: modelKey))
    }

    static func resolvedModelName(
        configuredModelName: String?,
        availableModels: [String],
        selectedModel: String,
        providerDefaultModel: String
    ) -> String {
        if let configuredModelName = nonEmptyString(configuredModelName),
           availableModels.isEmpty || availableModels.contains(configuredModelName) {
            return configuredModelName
        }

        if let selectedModel = nonEmptyString(selectedModel),
           availableModels.isEmpty || availableModels.contains(selectedModel) {
            return selectedModel
        }

        return availableModels.first ?? providerDefaultModel
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
