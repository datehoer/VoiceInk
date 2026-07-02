import SwiftUI
import AppKit
import LLMkit

struct CustomProviderManagementView: View {
    @ObservedObject var customModelManager: CustomCloudModelManager
    @ObservedObject var customAIProviderManager: CustomAIProviderManager

    let onAddTranscriptionModel: () -> Void
    let onEditTranscriptionModel: (CustomCloudModel) -> Void
    let onDeleteTranscriptionModel: (CustomCloudModel) -> Void
    let onAddEnhancementModel: () -> Void
    let onEditEnhancementModel: (CustomAIProviderConfig) -> Void
    let onDeleteEnhancementModel: (CustomAIProviderConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            customTranscriptionSection
            customEnhancementSection
        }
    }

    private var customTranscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Custom Transcription Models",
                subtitle: "Supports any provider that uses the same API format as OpenAI transcription.",
                addHelp: "Add transcription model",
                onAdd: onAddTranscriptionModel
            )

            if customModelManager.customModels.isEmpty {
                CustomProviderEmptyState(
                    systemImage: "waveform",
                    title: "No Custom Transcription Models"
                )
            } else {
                ForEach(customModelManager.customModels) { model in
                    CustomModelCardView(
                        model: model,
                        deleteAction: {
                            onDeleteTranscriptionModel(model)
                        },
                        editAction: onEditTranscriptionModel
                    )
                }
            }
        }
    }

    private var customEnhancementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Custom Enhancement Models",
                subtitle: "Supports any provider that uses the same API format as OpenAI chat completion.",
                addHelp: "Add enhancement model",
                onAdd: onAddEnhancementModel
            )

            if customAIProviderManager.providers.isEmpty {
                CustomProviderEmptyState(
                    systemImage: "sparkles",
                    title: "No Custom Enhancement Models"
                )
            } else {
                ForEach(customAIProviderManager.providers) { provider in
                    CustomEnhancementModelRow(
                        provider: provider,
                        onEdit: {
                            onEditEnhancementModel(provider)
                        },
                        onDelete: {
                            onDeleteEnhancementModel(provider)
                        }
                    )
                }
            }
        }
    }

    private func sectionHeader(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        addHelp: LocalizedStringResource,
        onAdd: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderSectionHeader(title: title, subtitle: subtitle)

            Spacer(minLength: 8)

            AddIconButton(helpText: addHelp, action: onAdd)
        }
    }

}

private struct CustomProviderEmptyState: View {
    let systemImage: String
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .background(ProviderSurface(cornerRadius: 10))
    }
}

private struct CustomEnhancementModelRow: View {
    let provider: CustomAIProviderConfig
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(AppTheme.Surface.control)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(provider.name)
                    .font(.system(size: 13, weight: .semibold))

                if provider.modelName.isEmpty {
                    Text("No model configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(modelSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
        }
        .padding(14)
        .background(ProviderSurface(cornerRadius: 10))
    }

    private var modelSummary: String {
        let modelCount = provider.trimmedModels.count
        if modelCount > 1 {
            return "\(provider.modelName) + \(modelCount - 1) more"
        }
        return provider.modelName
    }
}

struct CustomTranscriptionModelEditorPanel: View {
    let editingModel: CustomCloudModel?
    @ObservedObject var customModelManager: CustomCloudModelManager
    let onClose: () -> Void
    let onSave: () -> Void

    private let modelDiscoveryService = CustomModelDiscoveryService()

    @State private var displayName = ""
    @State private var apiEndpoint = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var requestMode: CustomTranscriptionRequestMode = .audioTranscriptions
    @State private var modelDiscoveryEndpoint = ""
    @State private var transcriptionPrompt = ""
    @State private var customBodyTemplate = CustomTranscriptionBodyTemplatePresets.chatAudioJSON
    @State private var isMultilingual = true
    @State private var validationErrors: [String] = []
    @State private var modelFetchError: String?
    @State private var fetchedModels: [String] = []
    @State private var isSaving = false
    @State private var isFetchingModels = false
    @State private var isAPIKeyVisible = false

    private var isEditing: Bool {
        editingModel != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader(title: isEditing ? "Edit Custom Transcription Model" : "Add Custom Transcription Model")

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CustomModelEditorSection(title: "Details") {
                        VStack(spacing: 10) {
                            CustomModelTextField(label: "Display Name", placeholder: String(localized: "My Custom Model"), text: $displayName)
                            CustomModelRequestModeRow(selection: $requestMode)
                            CustomModelTextField(label: "API Endpoint", placeholder: requestMode.defaultEndpoint, text: $apiEndpoint)
                            CustomModelAPIKeyField(label: "API Key", placeholder: String(localized: "Paste API key"), text: $apiKey, isRevealed: $isAPIKeyVisible)
                            CustomModelTextField(label: "Models URL", placeholder: derivedModelsEndpointPlaceholder, text: $modelDiscoveryEndpoint)
                            CustomModelModelPickerRow(
                                text: $modelName,
                                models: fetchedModels,
                                isFetching: isFetchingModels,
                                fetchAction: fetchModels
                            )
                            CustomModelPromptEditorRow(
                                label: "Prompt",
                                placeholder: String(localized: "Leave empty to use the global transcription prompt."),
                                text: $transcriptionPrompt
                            )
                            CustomModelToggleRow(title: "Multilingual Model", isOn: $isMultilingual)
                        }
                    }

                    if requestMode == .customJSON {
                        CustomModelEditorSection(title: "Body Template") {
                            VStack(alignment: .leading, spacing: 10) {
                                CustomModelTemplateToolbar(
                                    applyChatPreset: {
                                        customBodyTemplate = CustomTranscriptionBodyTemplatePresets.chatAudioJSON
                                    },
                                    applyInputPreset: {
                                        customBodyTemplate = CustomTranscriptionBodyTemplatePresets.simpleInputAudioJSON
                                    },
                                    insertPlaceholder: { placeholder in
                                        customBodyTemplate.append(placeholder)
                                    }
                                )

                                TextEditor(text: $customBodyTemplate)
                                    .font(.system(size: 11, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 220)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(AppTheme.Surface.control)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                                            )
                                    )
                            }
                        }
                    }

                    if let modelFetchError {
                        CustomModelErrorBox(messages: [modelFetchError])
                    }

                    if !validationErrors.isEmpty {
                        CustomModelErrorBox(messages: validationErrors)
                    }
                }
                .padding(20)
            }

            editorFooter(
                primaryTitle: isSaving ? "Saving" : isEditing ? "Save Changes" : "Add Model",
                isPrimaryDisabled: !canSave || isSaving,
                primaryAction: saveModel
            )
        }
        .onAppear(perform: loadModel)
        .onChange(of: editingModel?.id) { _, _ in
            loadModel()
        }
        .onChange(of: requestMode) { _, newMode in
            applyRequestModeDefaults(newMode)
        }
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (requestMode != .customJSON || !customBodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func loadModel() {
        if let editingModel {
            displayName = editingModel.displayName
            apiEndpoint = editingModel.apiEndpoint
            apiKey = editingModel.apiKey
            modelName = editingModel.modelName
            requestMode = editingModel.requestMode
            modelDiscoveryEndpoint = editingModel.modelDiscoveryEndpoint ?? ""
            transcriptionPrompt = editingModel.transcriptionPrompt ?? ""
            customBodyTemplate = editingModel.customBodyTemplate ?? CustomTranscriptionBodyTemplatePresets.chatAudioJSON
            isMultilingual = editingModel.isMultilingualModel
        } else {
            displayName = ""
            requestMode = .audioTranscriptions
            apiEndpoint = CustomTranscriptionRequestMode.audioTranscriptions.defaultEndpoint
            apiKey = ""
            modelName = "gpt-4o-mini-transcribe"
            modelDiscoveryEndpoint = ""
            transcriptionPrompt = ""
            customBodyTemplate = CustomTranscriptionBodyTemplatePresets.chatAudioJSON
            isMultilingual = true
        }

        validationErrors = []
        modelFetchError = nil
        fetchedModels = []
        isSaving = false
        isFetchingModels = false
        isAPIKeyVisible = false
    }

    private func saveModel() {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDiscoveryEndpoint = modelDiscoveryEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranscriptionPrompt = transcriptionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBodyTemplate = customBodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let generatedName = trimmedDisplayName.lowercased().replacingOccurrences(of: " ", with: "-")

        validationErrors = customModelManager.validateModelDetails(
            name: generatedName,
            displayName: trimmedDisplayName,
            apiEndpoint: trimmedEndpoint,
            modelName: trimmedModelName,
            excludingId: editingModel?.id
        )

        if trimmedKey.isEmpty {
            validationErrors.append(String(localized: "API key cannot be empty"))
        }

        if !trimmedDiscoveryEndpoint.isEmpty && URL(string: trimmedDiscoveryEndpoint)?.host == nil {
            validationErrors.append(String(localized: "Models URL must be a valid URL"))
        }

        if requestMode == .customJSON {
            do {
                _ = try OpenAICompatibleTranscriptionService.makeCustomJSONRequestBody(
                    audioData: Data([0x00]),
                    modelName: trimmedModelName,
                    context: TranscriptionRequestContext(language: "auto", prompt: ""),
                    audioFormat: "wav",
                    template: trimmedBodyTemplate
                )
            } catch {
                validationErrors.append(String(localized: "Custom JSON template must be valid JSON"))
            }
        }

        guard validationErrors.isEmpty else { return }
        isSaving = true

        let savedDiscoveryEndpoint = trimmedDiscoveryEndpoint.isEmpty ? nil : trimmedDiscoveryEndpoint
        let savedTranscriptionPrompt = TranscriptionPromptSettings.isDefaultSelection(trimmedTranscriptionPrompt) ? nil : trimmedTranscriptionPrompt
        let savedTemplate = requestMode == .customJSON ? trimmedBodyTemplate : nil

        if let editingModel {
            let updatedModel = CustomCloudModel(
                id: editingModel.id,
                name: generatedName,
                displayName: trimmedDisplayName,
                description: "Custom transcription model",
                apiEndpoint: trimmedEndpoint,
                modelName: trimmedModelName,
                requestMode: requestMode,
                modelDiscoveryEndpoint: savedDiscoveryEndpoint,
                transcriptionPrompt: savedTranscriptionPrompt,
                customBodyTemplate: savedTemplate,
                isMultilingual: isMultilingual
            )

            guard customModelManager.updateCustomModel(updatedModel, apiKey: trimmedKey) else {
                validationErrors = [String(localized: "Failed to save API key securely")]
                isSaving = false
                return
            }
        } else {
            let customModel = CustomCloudModel(
                name: generatedName,
                displayName: trimmedDisplayName,
                description: "Custom transcription model",
                apiEndpoint: trimmedEndpoint,
                modelName: trimmedModelName,
                requestMode: requestMode,
                modelDiscoveryEndpoint: savedDiscoveryEndpoint,
                transcriptionPrompt: savedTranscriptionPrompt,
                customBodyTemplate: savedTemplate,
                isMultilingual: isMultilingual
            )

            guard customModelManager.addCustomModel(customModel, apiKey: trimmedKey) else {
                validationErrors = [String(localized: "Failed to save API key securely")]
                isSaving = false
                return
            }
        }

        isSaving = false
        onSave()
    }

    private var derivedModelsEndpointPlaceholder: String {
        CustomModelDiscoveryEndpointResolver.endpoint(from: apiEndpoint)?.absoluteString ?? "https://api.openai.com/v1/models"
    }

    private func fetchModels() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            modelFetchError = String(localized: "API key cannot be empty")
            return
        }

        let trimmedModelsEndpoint = modelDiscoveryEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointURL: URL?
        if trimmedModelsEndpoint.isEmpty {
            endpointURL = CustomModelDiscoveryEndpointResolver.endpoint(from: apiEndpoint)
        } else {
            endpointURL = URL(string: trimmedModelsEndpoint)
        }

        guard let endpointURL, endpointURL.host != nil else {
            modelFetchError = String(localized: "Models URL must be a valid URL")
            return
        }

        isFetchingModels = true
        modelFetchError = nil

        Task {
            do {
                let models = try await modelDiscoveryService.fetchModels(endpoint: endpointURL, apiKey: trimmedKey)
                await MainActor.run {
                    fetchedModels = models
                    if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let firstModel = models.first {
                        modelName = firstModel
                    }
                    if trimmedModelsEndpoint.isEmpty {
                        modelDiscoveryEndpoint = endpointURL.absoluteString
                    }
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    fetchedModels = []
                    modelFetchError = error.localizedDescription
                    isFetchingModels = false
                }
            }
        }
    }

    private func applyRequestModeDefaults(_ newMode: CustomTranscriptionRequestMode) {
        let trimmedEndpoint = apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultEndpoints = Set(CustomTranscriptionRequestMode.allCases.map(\.defaultEndpoint))
        if trimmedEndpoint.isEmpty || defaultEndpoints.contains(trimmedEndpoint) {
            apiEndpoint = newMode.defaultEndpoint
        }

        if newMode == .customJSON && customBodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customBodyTemplate = CustomTranscriptionBodyTemplatePresets.chatAudioJSON
        }

        modelFetchError = nil
        fetchedModels = []
    }

    private func editorHeader(title: LocalizedStringKey) -> some View {
        CustomModelEditorHeader(title: title, onClose: onClose)
    }

    private func editorFooter(primaryTitle: LocalizedStringKey, isPrimaryDisabled: Bool, primaryAction: @escaping () -> Void) -> some View {
        CustomModelEditorFooter(
            primaryTitle: primaryTitle,
            isPrimaryDisabled: isPrimaryDisabled,
            onCancel: onClose,
            onPrimary: primaryAction
        )
    }
}

struct CustomEnhancementModelEditorPanel: View {
    let editingProvider: CustomAIProviderConfig?
    @ObservedObject var manager: CustomAIProviderManager
    let onClose: () -> Void
    let onSave: () -> Void

    private let modelDiscoveryService = CustomModelDiscoveryService()

    @State private var displayName = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var requestMode: CustomEnhancementRequestMode = .chatCompletions
    @State private var modelDiscoveryEndpoint = ""
    @State private var systemPrompt = ""
    @State private var customBodyTemplate = CustomEnhancementBodyTemplatePresets.chatCompletionsJSON
    @State private var errorMessage: String?
    @State private var modelFetchError: String?
    @State private var fetchedModels: [String] = []
    @State private var isSaving = false
    @State private var isVerifying = false
    @State private var isFetchingModels = false
    @State private var isAPIKeyVisible = false

    private var isEditing: Bool {
        editingProvider != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            CustomModelEditorHeader(
                title: isEditing ? "Edit Custom Enhancement Model" : "Add Custom Enhancement Model",
                onClose: onClose
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CustomModelEditorSection(title: "Details") {
                        VStack(spacing: 10) {
                            CustomModelTextField(label: "Display Name", placeholder: String(localized: "My Enhancement Model"), text: $displayName)
                            CustomEnhancementRequestModeRow(selection: $requestMode)
                            CustomModelTextField(label: "Base URL", placeholder: "https://api.openai.com/v1/chat/completions", text: $baseURL)
                            CustomModelAPIKeyField(label: "API Key", placeholder: String(localized: "Paste API key"), text: $apiKey, isRevealed: $isAPIKeyVisible)
                            CustomModelTextField(label: "Models URL", placeholder: derivedModelsEndpointPlaceholder, text: $modelDiscoveryEndpoint)
                            CustomModelModelPickerRow(
                                text: $modelName,
                                placeholder: "gpt-5.5",
                                models: fetchedModels,
                                isFetching: isFetchingModels,
                                fetchAction: fetchModels
                            )
                            CustomModelPromptEditorRow(
                                label: "Prompt",
                                placeholder: String(localized: "Optional system instructions for this model. Leave empty to use the selected enhancement prompt only."),
                                text: $systemPrompt
                            )
                        }
                    }

                    if requestMode == .customJSON {
                        CustomModelEditorSection(title: "Body Template") {
                            VStack(alignment: .leading, spacing: 10) {
                                CustomEnhancementTemplateToolbar(
                                    applyChatPreset: {
                                        customBodyTemplate = CustomEnhancementBodyTemplatePresets.chatCompletionsJSON
                                    },
                                    applyExplicitPreset: {
                                        customBodyTemplate = CustomEnhancementBodyTemplatePresets.explicitSystemUserJSON
                                    },
                                    insertPlaceholder: { placeholder in
                                        customBodyTemplate.append(placeholder)
                                    }
                                )

                                TextEditor(text: $customBodyTemplate)
                                    .font(.system(size: 11, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 220)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(AppTheme.Surface.control)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                                            )
                                    )
                            }
                        }
                    }

                    if let modelFetchError {
                        CustomModelErrorBox(messages: [modelFetchError])
                    }

                    if let errorMessage {
                        CustomModelErrorBox(messages: [errorMessage])
                    }
                }
                .padding(20)
            }

            CustomModelEditorFooter(
                primaryTitle: primaryButtonTitle,
                isPrimaryDisabled: !canSave || isSaving || isVerifying,
                onCancel: onClose,
                onPrimary: saveProvider
            )
        }
        .onAppear(perform: loadProvider)
        .onChange(of: editingProvider?.id) { _, _ in
            loadProvider()
        }
        .onChange(of: requestMode) { _, newMode in
            if newMode == .customJSON && customBodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customBodyTemplate = CustomEnhancementBodyTemplatePresets.chatCompletionsJSON
            }
        }
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (requestMode != .customJSON || !customBodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func loadProvider() {
        if let editingProvider {
            displayName = editingProvider.name
            baseURL = editingProvider.baseURL
            apiKey = APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: editingProvider.id) ?? ""
            modelName = editingProvider.modelName
            requestMode = editingProvider.customBodyTemplate == nil ? .chatCompletions : .customJSON
            modelDiscoveryEndpoint = editingProvider.modelDiscoveryEndpoint ?? ""
            systemPrompt = editingProvider.systemPrompt ?? ""
            customBodyTemplate = editingProvider.customBodyTemplate ?? CustomEnhancementBodyTemplatePresets.chatCompletionsJSON
            fetchedModels = editingProvider.trimmedModels
        } else {
            displayName = ""
            baseURL = "https://api.openai.com/v1/chat/completions"
            apiKey = ""
            modelName = "gpt-5.5"
            requestMode = .chatCompletions
            modelDiscoveryEndpoint = ""
            systemPrompt = ""
            customBodyTemplate = CustomEnhancementBodyTemplatePresets.chatCompletionsJSON
            fetchedModels = []
        }

        errorMessage = nil
        modelFetchError = nil
        isSaving = false
        isVerifying = false
        isFetchingModels = false
        isAPIKeyVisible = false
    }

    private var primaryButtonTitle: LocalizedStringKey {
        if isVerifying {
            return "Verifying"
        }

        if isSaving {
            return "Saving"
        }

        return isEditing ? "Save Changes" : "Add Model"
    }

    private func saveProvider() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDiscoveryEndpoint = modelDiscoveryEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBodyTemplate = customBodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines)

        var validationErrors = manager.validateProvider(
            name: trimmedName,
            baseURL: trimmedURL,
            model: trimmedModelName,
            excluding: editingProvider?.id
        )

        if trimmedKey.isEmpty {
            validationErrors.append(String(localized: "API key cannot be empty"))
        }

        if !trimmedDiscoveryEndpoint.isEmpty && URL(string: trimmedDiscoveryEndpoint)?.host == nil {
            validationErrors.append(String(localized: "Models URL must be a valid URL"))
        }

        if requestMode == .customJSON {
            do {
                _ = try CustomEnhancementRequestTemplateRenderer.makeRequestBody(
                    modelName: trimmedModelName,
                    systemPrompt: "System",
                    userMessage: "User",
                    temperature: 0.3,
                    template: trimmedBodyTemplate
                )
            } catch {
                validationErrors.append(String(localized: "Custom JSON template must be valid JSON"))
            }
        }

        guard validationErrors.isEmpty else {
            errorMessage = validationErrors.joined(separator: "\n")
            return
        }

        errorMessage = nil

        let provider = CustomAIProviderConfig(
            id: editingProvider?.id ?? UUID(),
            name: trimmedName,
            baseURL: trimmedURL,
            models: savedModels(selectedModel: trimmedModelName),
            selectedModel: trimmedModelName,
            modelDiscoveryEndpoint: trimmedDiscoveryEndpoint.isEmpty ? nil : trimmedDiscoveryEndpoint,
            systemPrompt: trimmedSystemPrompt.isEmpty ? nil : trimmedSystemPrompt,
            customBodyTemplate: requestMode == .customJSON ? trimmedBodyTemplate : nil
        )

        guard let verificationURL = URL(string: trimmedURL) else {
            errorMessage = String(localized: "Base URL must be a valid URL")
            return
        }

        isVerifying = true

        Task {
            let result = await CustomEnhancementRequestExecutor.verifyAPIKey(
                baseURL: verificationURL,
                apiKey: trimmedKey,
                modelName: trimmedModelName,
                bodyTemplate: provider.customBodyTemplate
            )

            await MainActor.run {
                isVerifying = false

                guard result.isValid else {
                    errorMessage = result.errorMessage ?? String(localized: "Could not verify this API key")
                    return
                }

                isSaving = true
                let didSave: Bool
                if isEditing {
                    didSave = manager.updateProvider(provider, apiKey: trimmedKey)
                } else {
                    didSave = manager.addProvider(provider, apiKey: trimmedKey)
                }
                isSaving = false

                if didSave {
                    onSave()
                } else {
                    errorMessage = String(localized: "Failed to save API key securely")
                }
            }
        }
    }

    private var derivedModelsEndpointPlaceholder: String {
        CustomModelDiscoveryEndpointResolver.endpoint(from: baseURL)?.absoluteString ?? "https://api.openai.com/v1/models"
    }

    private func fetchModels() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            modelFetchError = String(localized: "API key cannot be empty")
            return
        }

        let trimmedModelsEndpoint = modelDiscoveryEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointURL: URL?
        if trimmedModelsEndpoint.isEmpty {
            endpointURL = CustomModelDiscoveryEndpointResolver.endpoint(from: baseURL)
        } else {
            endpointURL = URL(string: trimmedModelsEndpoint)
        }

        guard let endpointURL, endpointURL.host != nil else {
            modelFetchError = String(localized: "Models URL must be a valid URL")
            return
        }

        isFetchingModels = true
        modelFetchError = nil

        Task {
            do {
                let models = try await modelDiscoveryService.fetchModels(endpoint: endpointURL, apiKey: trimmedKey)
                await MainActor.run {
                    fetchedModels = models
                    if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let firstModel = models.first {
                        modelName = firstModel
                    }
                    if trimmedModelsEndpoint.isEmpty {
                        modelDiscoveryEndpoint = endpointURL.absoluteString
                    }
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    fetchedModels = []
                    modelFetchError = error.localizedDescription
                    isFetchingModels = false
                }
            }
        }
    }

    private func savedModels(selectedModel: String) -> [String] {
        var models: [String] = []

        func appendUnique(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !models.contains(trimmed) else { return }
            models.append(trimmed)
        }

        fetchedModels.forEach(appendUnique)
        appendUnique(selectedModel)
        return models
    }
}

private enum CustomModelEditorMetrics {
    static let labelWidth: CGFloat = 104
    static let fieldMaxWidth: CGFloat = 236
}

private struct CustomModelEditorSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: () -> Content

    init(title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content()
            }
            .padding(12)
            .background(ProviderSurface(cornerRadius: 10))
        }
    }
}

private struct CustomModelTextField: View {
    let label: LocalizedStringKey
    let placeholder: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField("", text: $text, prompt: Text(verbatim: placeholder))
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .frame(maxWidth: CustomModelEditorMetrics.fieldMaxWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CustomModelPromptEditorRow: View {
    let label: LocalizedStringKey
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)
                .padding(.top, 7)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
            }
            .frame(maxWidth: CustomModelEditorMetrics.fieldMaxWidth, minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppTheme.Surface.control)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CustomModelRequestModeRow: View {
    @Binding var selection: CustomTranscriptionRequestMode

    var body: some View {
        HStack(spacing: 12) {
            Text("Request")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)

            Picker("", selection: $selection) {
                ForEach(CustomTranscriptionRequestMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: CustomModelEditorMetrics.fieldMaxWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CustomEnhancementRequestModeRow: View {
    @Binding var selection: CustomEnhancementRequestMode

    var body: some View {
        HStack(spacing: 12) {
            Text("Request")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)

            Picker("", selection: $selection) {
                ForEach(CustomEnhancementRequestMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: CustomModelEditorMetrics.fieldMaxWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CustomModelAPIKeyField: View {
    let label: LocalizedStringKey
    let placeholder: String
    @Binding var text: String
    @Binding var isRevealed: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)

            HStack(spacing: 6) {
                Group {
                    if isRevealed {
                        TextField("", text: $text, prompt: Text(verbatim: placeholder))
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 24)
                .help(isRevealed ? "Hide API key" : "Show API key")
            }
            .frame(maxWidth: CustomModelEditorMetrics.fieldMaxWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CustomModelModelPickerRow: View {
    @Binding var text: String
    var placeholder = "gpt-4o-mini-transcribe"
    let models: [String]
    let isFetching: Bool
    let fetchAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Model Name")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)

            HStack(spacing: 6) {
                TextField("", text: $text, prompt: Text(verbatim: placeholder))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                Menu {
                    if models.isEmpty {
                        Text("No fetched models")
                    } else {
                        ForEach(models, id: \.self) { model in
                            Button(model) {
                                text = model
                            }
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 24)
                .disabled(models.isEmpty)
                .help("Select fetched model")

                Button(action: fetchAction) {
                    if isFetching {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 24)
                .disabled(isFetching)
                .help("Fetch models")
            }
            .frame(maxWidth: CustomModelEditorMetrics.fieldMaxWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CustomModelTemplateToolbar: View {
    let applyChatPreset: () -> Void
    let applyInputPreset: () -> Void
    let insertPlaceholder: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu("Preset") {
                Button("Chat Audio JSON", action: applyChatPreset)
                Button("Responses Input Audio JSON", action: applyInputPreset)
            }

            Menu("Insert") {
                ForEach(CustomTranscriptionBodyTemplatePresets.placeholderTokens, id: \.self) { placeholder in
                    Button(placeholder) {
                        insertPlaceholder(placeholder)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }
}

private struct CustomEnhancementTemplateToolbar: View {
    let applyChatPreset: () -> Void
    let applyExplicitPreset: () -> Void
    let insertPlaceholder: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu("Preset") {
                Button("Chat Completions JSON", action: applyChatPreset)
                Button("System + User JSON", action: applyExplicitPreset)
            }

            Menu("Insert") {
                ForEach(CustomEnhancementBodyTemplatePresets.placeholderTokens, id: \.self) { placeholder in
                    Button(placeholder) {
                        insertPlaceholder(placeholder)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }
}

private struct CustomModelToggleRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)

            Toggle("", isOn: $isOn)
                .labelsHidden()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CustomModelErrorBox: View {
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(messages, id: \.self) { message in
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ProviderSurface(cornerRadius: 10))
    }
}

private struct CustomModelEditorHeader: View {
    let title: LocalizedStringKey
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(AppTheme.Surface.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }
}

private struct CustomModelEditorFooter: View {
    let primaryTitle: LocalizedStringKey
    let isPrimaryDisabled: Bool
    let onCancel: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button(primaryTitle, action: onPrimary)
                .buttonStyle(.borderedProminent)
                .disabled(isPrimaryDisabled)
        }
        .padding(20)
        .overlay(Divider().opacity(0.5), alignment: .top)
    }
}

#if DEBUG
private enum CustomModelsPreviewPanel {
    case transcription
    case enhancement
}

private struct CustomModelsSidePanelPreview: View {
    @State private var activePanel: CustomModelsPreviewPanel? = .transcription

    private var isPanelOpen: Binding<Bool> {
        Binding(
            get: { activePanel != nil },
            set: { if !$0 { activePanel = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            AppScreenHeader(title: "Model Catalog") {
                AppIconButton(systemName: "plus.circle.fill", help: "Add custom model") {
                    activePanel = .transcription
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    customSectionHeader(
                        title: "Custom Transcription Models",
                        subtitle: "Supports any provider that uses the same API format as OpenAI transcription.",
                        action: { activePanel = .transcription }
                    )

                    CustomModelCardView(
                        model: Self.sampleTranscriptionModel,
                        deleteAction: {},
                        editAction: { _ in activePanel = .transcription }
                    )

                    customSectionHeader(
                        title: "Custom Enhancement Models",
                        subtitle: "Supports any provider that uses the same API format as OpenAI chat completion.",
                        action: { activePanel = .enhancement }
                    )

                    CustomEnhancementModelRow(
                        provider: Self.sampleEnhancementProvider,
                        onEdit: { activePanel = .enhancement },
                        onDelete: {}
                    )
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 920, height: 640)
        .background(AppTheme.Surface.window)
        .sidePanel(isPresented: isPanelOpen) {
            panelContent
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch activePanel {
        case .transcription:
            CustomTranscriptionModelEditorPanel(
                editingModel: Self.sampleTranscriptionModel,
                customModelManager: .shared,
                onClose: { activePanel = nil },
                onSave: { activePanel = nil }
            )
        case .enhancement:
            CustomEnhancementModelEditorPanel(
                editingProvider: Self.sampleEnhancementProvider,
                manager: .shared,
                onClose: { activePanel = nil },
                onSave: { activePanel = nil }
            )
        case nil:
            EmptyView()
        }
    }

    private func customSectionHeader(title: LocalizedStringKey, subtitle: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderSectionHeader(title: title, subtitle: subtitle)

            Spacer()

            AddIconButton(helpText: "Add model", action: action)
        }
    }

    private static let sampleTranscriptionModel = CustomCloudModel(
        name: "acme-transcribe",
        displayName: "Acme Transcribe",
        description: "OpenAI-compatible transcription endpoint for previewing custom model cards.",
        apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
        modelName: "acme-transcribe-large",
        isMultilingual: true
    )

    private static let sampleEnhancementProvider = CustomAIProviderConfig(
        name: "Acme Enhance",
        baseURL: "https://api.example.com/v1/chat/completions",
        models: ["acme-enhance-pro"],
        selectedModel: "acme-enhance-pro"
    )
}

#Preview("Custom AI Models - Side Panel") {
    CustomModelsSidePanelPreview()
}
#endif
