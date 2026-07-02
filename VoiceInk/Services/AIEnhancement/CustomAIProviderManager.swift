import Foundation
import os

struct CustomAIProviderConfig: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var baseURL: String
    var models: [String]
    var selectedModel: String
    var modelDiscoveryEndpoint: String?
    var systemPrompt: String?
    var customBodyTemplate: String?

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        models: [String],
        selectedModel: String,
        modelDiscoveryEndpoint: String? = nil,
        systemPrompt: String? = nil,
        customBodyTemplate: String? = nil
    ) {
        let trimmedSystemPrompt = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.models = models
        self.selectedModel = selectedModel
        self.modelDiscoveryEndpoint = modelDiscoveryEndpoint
        self.systemPrompt = trimmedSystemPrompt.isEmpty ? nil : trimmedSystemPrompt
        self.customBodyTemplate = customBodyTemplate
    }

    var trimmedModels: [String] {
        models
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var modelName: String {
        let trimmedSelectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSelectedModel.isEmpty,
           trimmedModels.isEmpty || trimmedModels.contains(trimmedSelectedModel) {
            return trimmedSelectedModel
        }
        return trimmedModels.first ?? ""
    }

    func resolvedModelName(for requestedModelName: String) -> String {
        let trimmedRequestedModelName = requestedModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRequestedModelName.isEmpty, trimmedModels.contains(trimmedRequestedModelName) {
            return trimmedRequestedModelName
        }
        return modelName
    }

    var normalizedForStorage: CustomAIProviderConfig {
        let normalizedModels = Self.normalizedModelList(models: models, selectedModel: selectedModel)
        let trimmedSelectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModelName = normalizedModels.contains(trimmedSelectedModel) ? trimmedSelectedModel : normalizedModels.first ?? ""
        let trimmedDiscoveryEndpoint = modelDiscoveryEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedSystemPrompt = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedTemplate = customBodyTemplate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return CustomAIProviderConfig(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            models: normalizedModels,
            selectedModel: resolvedModelName,
            modelDiscoveryEndpoint: trimmedDiscoveryEndpoint.isEmpty ? nil : trimmedDiscoveryEndpoint,
            systemPrompt: trimmedSystemPrompt.isEmpty ? nil : trimmedSystemPrompt,
            customBodyTemplate: trimmedTemplate.isEmpty ? nil : trimmedTemplate
        )
    }

    private static func normalizedModelList(models: [String], selectedModel: String) -> [String] {
        var normalized: [String] = []

        func appendUnique(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !normalized.contains(trimmed) else { return }
            normalized.append(trimmed)
        }

        models.forEach(appendUnique)
        appendUnique(selectedModel)
        return normalized
    }
}

struct CustomAIProviderRequestConfiguration {
    let baseURL: String
    let apiKey: String
    let modelName: String
    let systemPrompt: String?
    let customBodyTemplate: String?

    func effectiveSystemPrompt(fallback: String) -> String {
        let trimmedSystemPrompt = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedSystemPrompt.isEmpty {
            return trimmedFallback
        }

        if trimmedFallback.isEmpty {
            return trimmedSystemPrompt
        }

        return "\(trimmedSystemPrompt)\n\n\(trimmedFallback)"
    }
}

final class CustomAIProviderManager: ObservableObject {
    static let shared = CustomAIProviderManager()

    @Published private(set) var providers: [CustomAIProviderConfig] = []

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CustomAIProviderManager")
    private let providersKey = "customAIProviders"
    private let defaults = UserDefaults.standard

    private init() {
        loadProviders()
        migrateLegacyCustomProviderIfNeeded()
    }

    var availableModelNames: [String] {
        providers.reduce(into: [String]()) { result, provider in
            guard hasAPIKey(for: provider) else { return }

            let modelNames = provider.trimmedModels.isEmpty ? [provider.modelName] : provider.trimmedModels
            for modelName in modelNames where !modelName.isEmpty && !result.contains(modelName) {
                result.append(modelName)
            }
        }
    }

    var defaultModelName: String {
        let savedModel = defaults.string(forKey: "customProviderModel")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let configuredModelNames = availableModelNames
        if !savedModel.isEmpty, configuredModelNames.contains(savedModel) {
            return savedModel
        }

        return configuredModelNames.first ?? ""
    }

    var hasConfiguredModels: Bool {
        providers.contains { provider in
            !provider.modelName.isEmpty && hasAPIKey(for: provider)
        }
    }

    @discardableResult
    func addProvider(_ provider: CustomAIProviderConfig, apiKey: String) -> Bool {
        let normalizedProvider = provider.normalizedForStorage
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty,
              APIKeyManager.shared.saveCustomAIProviderAPIKey(trimmedKey, forProviderId: normalizedProvider.id) else {
            return false
        }

        providers.append(normalizedProvider)
        saveProviders()

        return true
    }

    func updateProvider(_ provider: CustomAIProviderConfig, apiKey: String? = nil) -> Bool {
        let normalizedProvider = provider.normalizedForStorage
        guard let index = providers.firstIndex(where: { $0.id == normalizedProvider.id }) else {
            return false
        }

        if let apiKey {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty,
                  APIKeyManager.shared.saveCustomAIProviderAPIKey(trimmedKey, forProviderId: normalizedProvider.id) else {
                return false
            }
        }

        let previousProvider = providers[index]
        let selectedModelName = defaults.string(forKey: "customProviderModel")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wasPreviousProviderSelected = selectedModelName == previousProvider.modelName ||
            previousProvider.trimmedModels.contains(selectedModelName)
        let shouldApplyRuntimeConfiguration = wasPreviousProviderSelected ||
            selectedModelName == normalizedProvider.modelName ||
            normalizedProvider.trimmedModels.contains(selectedModelName)
        let runtimeModelName = normalizedProvider.trimmedModels.contains(selectedModelName)
            ? selectedModelName
            : normalizedProvider.modelName

        providers[index] = normalizedProvider
        saveProviders(notifySettingsChange: !shouldApplyRuntimeConfiguration)

        if shouldApplyRuntimeConfiguration {
            applyRuntimeConfiguration(normalizedProvider, selectedModelName: runtimeModelName)
        }

        return true
    }

    func deleteProvider(_ provider: CustomAIProviderConfig) {
        providers.removeAll { $0.id == provider.id }
        APIKeyManager.shared.deleteCustomAIProviderAPIKey(forProviderId: provider.id)

        let selectedModelName = defaults.string(forKey: "customProviderModel")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if selectedModelName == provider.modelName || provider.trimmedModels.contains(selectedModelName) {
            clearRuntimeConfiguration()
        }

        saveProviders()
    }

    @discardableResult
    func applyConfiguration(forModel modelName: String) -> Bool {
        guard let provider = provider(forModel: modelName) else { return false }
        guard hasAPIKey(for: provider) else { return false }
        applyRuntimeConfiguration(provider, selectedModelName: provider.resolvedModelName(for: modelName))
        return true
    }

    func provider(forModel modelName: String) -> CustomAIProviderConfig? {
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelName.isEmpty else { return nil }

        return providers.first {
            $0.modelName == trimmedModelName || $0.trimmedModels.contains(trimmedModelName)
        }
    }

    func requestConfiguration(forModel modelName: String) -> CustomAIProviderRequestConfiguration? {
        guard let provider = provider(forModel: modelName),
              let apiKey = APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: provider.id),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return CustomAIProviderRequestConfiguration(
            baseURL: provider.baseURL,
            apiKey: apiKey,
            modelName: provider.resolvedModelName(for: modelName),
            systemPrompt: provider.systemPrompt,
            customBodyTemplate: provider.customBodyTemplate
        )
    }

    func validateProvider(name: String, baseURL: String, model: String, excluding id: UUID? = nil) -> [String] {
        var errors: [String] = []
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            errors.append(String(localized: "Display name cannot be empty"))
        }

        if trimmedURL.isEmpty {
            errors.append(String(localized: "Base URL cannot be empty"))
        } else if URL(string: trimmedURL)?.host == nil {
            errors.append(String(localized: "Base URL must be a valid URL"))
        }

        if trimmedModel.isEmpty {
            errors.append(String(localized: "Model name cannot be empty"))
        }

        if providers.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame && $0.id != id }) {
            errors.append(String(localized: "A custom enhancement model with this display name already exists"))
        }

        if providers.contains(where: { provider in
            provider.id != id &&
                provider.trimmedModels.contains { $0.caseInsensitiveCompare(trimmedModel) == .orderedSame }
        }) {
            errors.append(String(localized: "A custom enhancement model with this model name already exists"))
        }

        return errors
    }

    private func loadProviders() {
        guard let data = defaults.data(forKey: providersKey) else { return }
        do {
            providers = try JSONDecoder().decode([CustomAIProviderConfig].self, from: data)
        } catch {
            logger.error("Failed to decode custom AI providers: \(error, privacy: .public)")
            providers = []
        }
    }

    private func saveProviders(notifySettingsChange: Bool = true) {
        do {
            let data = try JSONEncoder().encode(providers)
            defaults.set(data, forKey: providersKey)
            if notifySettingsChange {
                NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            }
        } catch {
            logger.error("Failed to encode custom AI providers: \(error, privacy: .public)")
        }
    }

    private func hasAPIKey(for provider: CustomAIProviderConfig) -> Bool {
        guard let key = APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: provider.id) else {
            return false
        }

        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func migrateLegacyCustomProviderIfNeeded() {
        guard providers.isEmpty,
              let baseURL = defaults.string(forKey: "customProviderBaseURL"),
              !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let model = defaults.string(forKey: "customProviderModel"),
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let provider = CustomAIProviderConfig(
            name: "Custom",
            baseURL: baseURL,
            models: [model],
            selectedModel: model
        )
        providers = [provider]

        if let legacyKey = APIKeyManager.shared.getAPIKey(forProvider: AIProvider.custom.rawValue) {
            APIKeyManager.shared.saveCustomAIProviderAPIKey(legacyKey, forProviderId: provider.id)
        }

        saveProviders()
    }

    private func applyRuntimeConfiguration(_ provider: CustomAIProviderConfig, selectedModelName: String? = nil) {
        let requestedModelName = selectedModelName ?? provider.modelName
        let modelName = provider.resolvedModelName(for: requestedModelName)

        defaults.set(provider.baseURL, forKey: "customProviderBaseURL")
        defaults.set(modelName, forKey: "customProviderModel")
        defaults.set(modelName, forKey: "\(AIProvider.custom.rawValue)SelectedModel")

        if let key = APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: provider.id), !key.isEmpty {
            APIKeyManager.shared.saveAPIKey(key, forProvider: AIProvider.custom.rawValue)
        }

        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private func clearRuntimeConfiguration() {
        defaults.removeObject(forKey: "customProviderBaseURL")
        defaults.removeObject(forKey: "customProviderModel")
        defaults.removeObject(forKey: "\(AIProvider.custom.rawValue)SelectedModel")
        APIKeyManager.shared.deleteAPIKey(forProvider: AIProvider.custom.rawValue)
        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
}
