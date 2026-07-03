//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Foundation
import Testing
@testable import VoiceInk

struct VoiceInkTests {

    @Test func customChatCompletionsTranscriptionRequestUsesInputAudioJSON() throws {
        let audioData = Data([0x52, 0x49, 0x46, 0x46])
        let body = try OpenAICompatibleTranscriptionService.makeChatCompletionsRequestBody(
            audioData: audioData,
            modelName: "models/gemini-3.5-flash",
            context: TranscriptionRequestContext(
                language: "auto",
                prompt: "Use product names exactly."
            ),
            audioFormat: "wav"
        )

        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "models/gemini-3.5-flash")
        #expect(object["temperature"] as? Double == 0)

        let messages = try #require(object["messages"] as? [[String: Any]])
        let userMessage = try #require(messages.first)
        #expect(userMessage["role"] as? String == "user")

        let content = try #require(userMessage["content"] as? [[String: Any]])
        #expect(content.contains { part in
            part["type"] as? String == "text" &&
                (part["text"] as? String)?.contains("Use product names exactly.") == true
        })
        #expect(content.contains { part in
            guard part["type"] as? String == "input_audio",
                  let inputAudio = part["input_audio"] as? [String: Any] else {
                return false
            }
            return inputAudio["format"] as? String == "wav" &&
                inputAudio["data"] as? String == audioData.base64EncodedString()
        })
    }

    @Test func customRequestModeMigratesFromLegacyEndpointPath() throws {
        let legacyJSON = """
        {
          "id": "72D5EF0B-ABCE-4D6D-8215-ED2F58A8E1C4",
          "name": "gemini",
          "displayName": "Gemini",
          "description": "Custom transcription model",
          "apiEndpoint": "https://api.example.com/v1/chat/completions",
          "modelName": "models/gemini-3.5-flash",
          "isMultilingualModel": true,
          "supportedLanguages": { "en": "English" }
        }
        """.data(using: .utf8)!

        let model = try JSONDecoder().decode(CustomCloudModel.self, from: legacyJSON)

        #expect(model.requestMode == .chatCompletions)
        #expect(model.modelDiscoveryEndpoint == nil)
        #expect(model.customBodyTemplate == nil)
    }

    @Test func transcriptionRequestContextKeepsPromptForCloudModels() {
        let context = TranscriptionRequestContext(language: "en", prompt: "Use product names exactly.")
        let cloudModel = CloudModel(
            name: "whisper-large-v3-turbo",
            displayName: "Groq Whisper",
            description: "OpenAI-compatible cloud transcription",
            provider: .groq,
            speed: 0.65,
            accuracy: 0.95,
            isMultilingual: true,
            supportedLanguages: ["en": "English"]
        )
        let customModel = CustomCloudModel(
            name: "custom-transcribe",
            displayName: "Custom Transcribe",
            description: "Custom transcription model",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            modelName: "whisper-1"
        )

        #expect(context.scoped(to: cloudModel).prompt == "Use product names exactly.")
        #expect(context.scoped(to: customModel).prompt == "Use product names exactly.")
    }

    @Test func customTranscriptionModelPromptOverridesGlobalPromptInRequests() throws {
        let model = CustomCloudModel(
            name: "custom-transcribe",
            displayName: "Custom Transcribe",
            description: "Custom transcription model",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            modelName: "whisper-1",
            transcriptionPrompt: "Prefer Acme product names and keep issue IDs verbatim."
        )
        let context = TranscriptionRequestContext(
            language: "en",
            prompt: "Global prompt should not be sent."
        )
        let scopedContext = context.scoped(to: model)

        let body = OpenAICompatibleTranscriptionService.makeAudioTranscriptionsRequestBody(
            audioData: Data([0x01, 0x02]),
            fileName: "sample.wav",
            modelName: model.modelName,
            boundary: "Boundary-Test",
            context: scopedContext
        )
        let bodyString = try #require(String(data: body, encoding: .utf8))

        #expect(scopedContext.prompt == "Prefer Acme product names and keep issue IDs verbatim.")
        #expect(bodyString.contains("Prefer Acme product names and keep issue IDs verbatim."))
        #expect(!bodyString.contains("Global prompt should not be sent."))
    }

    @Test func transcriptionPromptFallsBackToDefaultWhenUnsetOrBlank() throws {
        let defaults = try #require(UserDefaults(suiteName: "VoiceInkTests.TranscriptionPrompt.\(UUID().uuidString)"))
        defaults.removeObject(forKey: TranscriptionPromptSettings.userDefaultsKey)

        #expect(TranscriptionPromptSettings.currentPrompt(in: defaults) == TranscriptionPromptSettings.defaultPrompt)

        defaults.set("   \n", forKey: TranscriptionPromptSettings.userDefaultsKey)
        #expect(TranscriptionPromptSettings.currentPrompt(in: defaults) == TranscriptionPromptSettings.defaultPrompt)
        #expect(TranscriptionRequestContext(language: "en", prompt: nil).effectivePrompt == TranscriptionPromptSettings.defaultPrompt)
    }

    @Test func transcriptionPromptMigratesLegacyLanguageSampleToDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "VoiceInkTests.LegacyTranscriptionPrompt.\(UUID().uuidString)"))
        defaults.set("Hello, how are you doing? Nice to meet you.", forKey: TranscriptionPromptSettings.userDefaultsKey)

        #expect(TranscriptionPromptSettings.currentPrompt(in: defaults) == TranscriptionPromptSettings.defaultPrompt)

        defaults.set("你好，最近好吗？见到你很高兴。", forKey: TranscriptionPromptSettings.userDefaultsKey)
        #expect(TranscriptionPromptSettings.currentPrompt(in: defaults) == TranscriptionPromptSettings.defaultPrompt)
    }

    @Test func openAIAudioTranscriptionsRequestIncludesPromptField() throws {
        let boundary = "Boundary-Test"
        let body = OpenAICompatibleTranscriptionService.makeAudioTranscriptionsRequestBody(
            audioData: Data([0x01, 0x02]),
            fileName: "sample.wav",
            modelName: "whisper-1",
            boundary: boundary,
            context: TranscriptionRequestContext(language: "en", prompt: "Use product names exactly.")
        )
        let bodyString = try #require(String(data: body, encoding: .utf8))

        #expect(bodyString.contains("name=\"prompt\""))
        #expect(bodyString.contains("Use product names exactly."))
    }

    @Test func openAIAudioTranscriptionsRequestIncludesDefaultPromptField() throws {
        let boundary = "Boundary-Test"
        let body = OpenAICompatibleTranscriptionService.makeAudioTranscriptionsRequestBody(
            audioData: Data([0x01, 0x02]),
            fileName: "sample.wav",
            modelName: "whisper-1",
            boundary: boundary,
            context: TranscriptionRequestContext(language: "en", prompt: nil)
        )
        let bodyString = try #require(String(data: body, encoding: .utf8))

        #expect(bodyString.contains("name=\"prompt\""))
        #expect(bodyString.contains(TranscriptionPromptSettings.defaultPrompt))
    }

    @Test func modelDiscoveryEndpointIsDerivedFromCommonOpenAICompatiblePaths() throws {
        #expect(
            CustomModelDiscoveryEndpointResolver.endpoint(from: "https://api.example.com/v1/audio/transcriptions")?
                .absoluteString == "https://api.example.com/v1/models"
        )
        #expect(
            CustomModelDiscoveryEndpointResolver.endpoint(from: "https://api.example.com/v1/chat/completions")?
                .absoluteString == "https://api.example.com/v1/models"
        )
        #expect(
            CustomModelDiscoveryEndpointResolver.endpoint(from: "https://api.example.com/openai/deployments/transcribe/audio/transcriptions")?
                .absoluteString == "https://api.example.com/openai/deployments/transcribe/models"
        )
    }

    @Test func modelDiscoveryParsesOpenAICompatibleAndGeminiStylePayloads() throws {
        let openAIModels = try CustomModelDiscoveryResponseParser.modelNames(
            from: """
            { "data": [{ "id": "gpt-4o-mini-transcribe" }, { "id": "whisper-1" }] }
            """.data(using: .utf8)!
        )

        #expect(openAIModels == ["gpt-4o-mini-transcribe", "whisper-1"])

        let geminiModels = try CustomModelDiscoveryResponseParser.modelNames(
            from: """
            { "models": [{ "name": "models/gemini-3.5-flash" }, { "name": "models/gemini-2.5-flash" }] }
            """.data(using: .utf8)!
        )

        #expect(geminiModels == ["models/gemini-3.5-flash", "models/gemini-2.5-flash"])
    }

    @Test func customJSONTemplateReplacesAudioAndModelPlaceholders() throws {
        let audioData = Data([0x01, 0x02, 0x03])
        let body = try OpenAICompatibleTranscriptionService.makeCustomJSONRequestBody(
            audioData: audioData,
            modelName: "models/gemini-3.5-flash",
            context: TranscriptionRequestContext(language: "en", prompt: "medical names"),
            audioFormat: "wav",
            template: """
            {
              "model": "{{model}}",
              "messages": [
                {
                  "role": "user",
                  "content": [
                    { "type": "text", "text": "Prompt: {{prompt}} Language: {{language}}" },
                    { "type": "input_audio", "input_audio": { "data": "{{audio_base64}}", "format": "{{audio_format}}" } }
                  ]
                }
              ],
              "temperature": {{temperature}}
            }
            """
        )

        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "models/gemini-3.5-flash")
        #expect(object["temperature"] as? Double == 0)

        let messages = try #require(object["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(content.contains { part in
            part["type"] as? String == "text" &&
                (part["text"] as? String)?.contains("Prompt: medical names Language: en") == true
        })
        #expect(content.contains { part in
            guard part["type"] as? String == "input_audio",
                  let inputAudio = part["input_audio"] as? [String: Any] else {
                return false
            }
            return inputAudio["data"] as? String == audioData.base64EncodedString() &&
                inputAudio["format"] as? String == "wav"
        })
    }

    @Test func transcriptionResponseDecoderHandlesCommonCustomJSONShapes() throws {
        let textResponse = try OpenAICompatibleTranscriptionService.decodeTranscriptionText(
            from: #"{"text":"hello world"}"#.data(using: .utf8)!,
            requestMode: .customJSON
        )
        let chatResponse = try OpenAICompatibleTranscriptionService.decodeTranscriptionText(
            from: #"{"choices":[{"message":{"content":"chat text"}}]}"#.data(using: .utf8)!,
            requestMode: .customJSON
        )

        #expect(textResponse == "hello world")
        #expect(chatResponse == "chat text")
    }

    @Test func customEnhancementProviderPreservesFetchedModelsAndTemplateSettings() throws {
        let providerId = try #require(UUID(uuidString: "8D2D30F5-C24C-4D8D-9E52-8AB4BD6728E2"))
        let provider = CustomAIProviderConfig(
            id: providerId,
            name: "New API",
            baseURL: "https://api.example.com/v1/chat/completions",
            models: [" models/gemini-3.5-flash ", "models/gemini-3.5-pro", "models/gemini-3.5-flash", " "],
            selectedModel: "models/gemini-3.5-pro",
            modelDiscoveryEndpoint: "https://api.example.com/v1/models",
            systemPrompt: "  Always preserve markdown tables.  ",
            customBodyTemplate: #"{"model":"{{model}}","messages":{{messages_json}}}"#
        )

        let stored = provider.normalizedForStorage

        #expect(stored.models == ["models/gemini-3.5-flash", "models/gemini-3.5-pro"])
        #expect(stored.selectedModel == "models/gemini-3.5-pro")
        #expect(stored.modelDiscoveryEndpoint == "https://api.example.com/v1/models")
        #expect(stored.systemPrompt == "Always preserve markdown tables.")
        #expect(stored.customBodyTemplate == #"{"model":"{{model}}","messages":{{messages_json}}}"#)
    }

    @Test func customEnhancementProviderSystemPromptCombinesWithSelectedPrompt() {
        let configuration = CustomAIProviderRequestConfiguration(
            baseURL: "https://api.example.com/v1/chat/completions",
            apiKey: "sk-test",
            modelName: "models/gemini-3.5-flash",
            systemPrompt: "Always preserve markdown tables.",
            customBodyTemplate: nil
        )

        #expect(
            configuration.effectiveSystemPrompt(fallback: "Rewrite clearly.") ==
                "Always preserve markdown tables.\n\nRewrite clearly."
        )
    }

    @Test func customModelEditorRoutesUseCenteredDialogPresentation() {
        let modelID = UUID()
        let providerID = UUID()

        #expect(ModelManagementCustomEditorRoute.transcription(modelID).presentationStyle == .centeredDialog)
        #expect(ModelManagementCustomEditorRoute.enhancement(providerID).presentationStyle == .centeredDialog)
        #expect(ModelManagementCustomEditorRoute.transcription(modelID).id == "custom-transcription-\(modelID.uuidString)")
        #expect(ModelManagementCustomEditorRoute.enhancement(providerID).id == "custom-enhancement-\(providerID.uuidString)")
        #expect(ModelManagementCustomEditorRoute.transcription(nil).id == "custom-transcription-new")
    }

    @Test func customModelRowsExposeEditAndDeleteActionsAsSeparateButtons() {
        #expect(CustomModelRowAction.visibleActions == [.edit, .delete])
        #expect(CustomModelRowAction.edit.systemImage == "pencil")
        #expect(CustomModelRowAction.delete.systemImage == "trash")
        #expect(CustomModelRowAction.delete.isDestructive == true)
    }

    @Test func customModelEditorUsesModernModalLayoutMetrics() {
        #expect(CustomModelEditorMetrics.modalWidth == 600)
        #expect(CustomModelEditorMetrics.modalHeight == 720)
        #expect(CustomModelEditorMetrics.labelWidth == 120)
        #expect(CustomModelEditorMetrics.controlWidth == 416)
        #expect(CustomModelEditorMetrics.bodyHorizontalPadding == 24)
        #expect(CustomModelEditorMetrics.sectionSpacing == 20)
        #expect(CustomModelEditorMetrics.controlCornerRadius == 8)
        #expect(CustomModelEditorMetrics.outerCornerRadius == 12)
    }

    @Test func customEnhancementJSONTemplateReplacesChatPlaceholders() throws {
        let body = try CustomEnhancementRequestTemplateRenderer.makeRequestBody(
            modelName: "models/gemini-3.5-flash",
            systemPrompt: "Use \"clean\" formatting.",
            userMessage: "hello\nworld",
            temperature: 0.3,
            template: """
            {
              "model": "{{model}}",
              "messages": {{messages_json}},
              "metadata": {
                "system": "{{system_prompt}}",
                "user": "{{user_message}}"
              },
              "temperature": {{temperature}},
              "stream": false
            }
            """
        )

        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "models/gemini-3.5-flash")
        #expect(object["temperature"] as? Double == 0.3)
        #expect(object["stream"] as? Bool == false)

        let metadata = try #require(object["metadata"] as? [String: Any])
        #expect(metadata["system"] as? String == "Use \"clean\" formatting.")
        #expect(metadata["user"] as? String == "hello\nworld")

        let messages = try #require(object["messages"] as? [[String: String]])
        #expect(messages == [
            ["role": "system", "content": "Use \"clean\" formatting."],
            ["role": "user", "content": "hello\nworld"]
        ])
    }

    @Test func customEnhancementVerificationRejectsInvalidTemplateBeforeNetwork() async throws {
        let url = try #require(URL(string: "https://api.example.com/v1/chat/completions"))

        let result = await CustomEnhancementRequestExecutor.verifyAPIKey(
            baseURL: url,
            apiKey: "sk-test",
            modelName: "models/gemini-3.5-flash",
            bodyTemplate: #"{"model":"{{model}""#
        )

        #expect(result.isValid == false)
        #expect(result.errorMessage == "Custom JSON template must be valid JSON")
    }

    @Test func starterModeDefaultPolicyPrefersEnhancementWhenAvailable() {
        #expect(StarterModeDefaultPolicy.defaultKind(for: [.clean]) == .clean)
        #expect(StarterModeDefaultPolicy.defaultKind(for: [.clean, .enhance]) == .enhance)
        #expect(StarterModeDefaultPolicy.defaultTemplateID(for: [.clean, .enhance]) == StarterModeCatalog.enhancementModeID)
    }

    @Test func starterModeDefaultMigrationPromotesInstalledDictationDefaultToEnhancement() throws {
        let activeID = StarterModeCatalog.cleanModeID
        let result = StarterModeEnhancementDefaultMigration.upgraded(
            configurations: [
                ModeConfig(
                    id: StarterModeCatalog.cleanModeID,
                    name: "Dictation",
                    isAIEnhancementEnabled: false,
                    isDefault: true
                ),
                ModeConfig(
                    id: StarterModeCatalog.enhancementModeID,
                    name: "Enhancement",
                    isAIEnhancementEnabled: true,
                    selectedPrompt: PromptTemplates.defaultPromptId.uuidString,
                    selectedAIProvider: AIProvider.gemini.rawValue,
                    selectedAIModel: AIProvider.gemini.defaultModel,
                    isDefault: false
                )
            ],
            activeConfigurationID: activeID
        )

        let cleanMode = try #require(result.configurations.first { $0.id == StarterModeCatalog.cleanModeID })
        let enhancementMode = try #require(result.configurations.first { $0.id == StarterModeCatalog.enhancementModeID })

        #expect(result.didChange)
        #expect(cleanMode.isDefault == false)
        #expect(enhancementMode.isDefault == true)
        #expect(enhancementMode.isAIEnhancementEnabled == true)
        #expect(result.activeConfigurationID == StarterModeCatalog.enhancementModeID)
    }

    @Test func starterModeDefaultMigrationPreservesCustomDefaultMode() {
        let customID = UUID()
        let result = StarterModeEnhancementDefaultMigration.upgraded(
            configurations: [
                ModeConfig(
                    id: StarterModeCatalog.cleanModeID,
                    name: "Dictation",
                    isAIEnhancementEnabled: false,
                    isDefault: false
                ),
                ModeConfig(
                    id: StarterModeCatalog.enhancementModeID,
                    name: "Enhancement",
                    isAIEnhancementEnabled: true,
                    selectedPrompt: PromptTemplates.defaultPromptId.uuidString,
                    selectedAIProvider: AIProvider.gemini.rawValue,
                    selectedAIModel: AIProvider.gemini.defaultModel,
                    isDefault: false
                ),
                ModeConfig(
                    id: customID,
                    name: "Custom workflow",
                    isAIEnhancementEnabled: false,
                    isDefault: true
                )
            ],
            activeConfigurationID: customID
        )

        #expect(result.didChange == false)
        #expect(result.configurations.first { $0.id == customID }?.isDefault == true)
        #expect(result.activeConfigurationID == customID)
    }

    @Test func newModeDraftInheritsEnhancementStateFromEffectiveMode() {
        let enhancementMode = ModeConfig(
            name: "Enhancement",
            isAIEnhancementEnabled: true,
            selectedPrompt: PromptTemplates.defaultPromptId.uuidString,
            selectedAIProvider: AIProvider.gemini.rawValue,
            selectedAIModel: AIProvider.gemini.defaultModel
        )
        let dictationMode = ModeConfig(
            name: "Dictation",
            isAIEnhancementEnabled: false
        )

        #expect(ModeConfigDraft.defaultEnhancementEnabled(inheriting: enhancementMode) == true)
        #expect(ModeConfigDraft.defaultEnhancementEnabled(inheriting: dictationMode) == false)
        #expect(ModeConfigDraft.defaultEnhancementEnabled(inheriting: nil) == false)
    }

    @Test func enhancementRuntimeFallbackEnablesOnlyWhenNoModeHasPromptAndProvider() {
        let prompt = CustomPrompt(title: "Default", promptText: "Clean up dictated text.")
        let disabledMode = ModeConfig(
            name: "Dictation",
            isAIEnhancementEnabled: false
        )
        let enabledMode = ModeConfig(
            name: "Enhancement",
            isAIEnhancementEnabled: true
        )

        #expect(ModeRuntimeResolver.defaultEnhancementEnabled(mode: nil, prompt: prompt, provider: .gemini) == true)
        #expect(ModeRuntimeResolver.defaultEnhancementEnabled(mode: nil, prompt: nil, provider: .gemini) == false)
        #expect(ModeRuntimeResolver.defaultEnhancementEnabled(mode: nil, prompt: prompt, provider: nil) == false)
        #expect(ModeRuntimeResolver.defaultEnhancementEnabled(mode: nil, prompt: prompt, provider: .gemini, defaultEnhancementEnabled: false) == false)
        #expect(ModeRuntimeResolver.defaultEnhancementEnabled(mode: disabledMode, prompt: prompt, provider: .gemini) == false)
        #expect(ModeRuntimeResolver.defaultEnhancementEnabled(mode: enabledMode, prompt: nil, provider: nil) == true)
    }

    @Test func defaultEnhancementModelSelectionKeepsConfiguredValidModel() {
        let options = ["gemini-3.5-flash", "gemini-2.5-pro"]

        #expect(DefaultEnhancementSettings.resolvedModelName(
            configuredModelName: "gemini-2.5-pro",
            availableModels: options,
            selectedModel: "gemini-3.5-flash",
            providerDefaultModel: "gemini-3.5-flash"
        ) == "gemini-2.5-pro")

        #expect(DefaultEnhancementSettings.resolvedModelName(
            configuredModelName: "missing-model",
            availableModels: options,
            selectedModel: "gemini-3.5-flash",
            providerDefaultModel: "gemini-3.5-flash"
        ) == "gemini-3.5-flash")
    }

    @Test func defaultEnhancementSettingDefaultsToEnabledUntilUserDisablesIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "VoiceInkTests.defaultEnhancement"))
        defaults.removePersistentDomain(forName: "VoiceInkTests.defaultEnhancement")
        defer { defaults.removePersistentDomain(forName: "VoiceInkTests.defaultEnhancement") }

        #expect(DefaultEnhancementSettings.isEnabled(in: defaults) == true)

        defaults.set(false, forKey: DefaultEnhancementSettings.isEnabledKey)
        #expect(DefaultEnhancementSettings.isEnabled(in: defaults) == false)
    }

    @Test func enhancementPromptStoreSeedsBuiltInPromptsWhenUnset() throws {
        let defaults = try #require(UserDefaults(suiteName: "VoiceInkTests.promptStore.seed"))
        defaults.removePersistentDomain(forName: "VoiceInkTests.promptStore.seed")
        defer { defaults.removePersistentDomain(forName: "VoiceInkTests.promptStore.seed") }

        let prompts = EnhancementPromptStore.loadPrompts(from: defaults)

        #expect(prompts.contains { $0.id == PromptTemplates.defaultPromptId })
        #expect(prompts.isEmpty == false)
    }

    @Test func enhancementPromptStorePreservesSavedPrompts() throws {
        let defaults = try #require(UserDefaults(suiteName: "VoiceInkTests.promptStore.saved"))
        defaults.removePersistentDomain(forName: "VoiceInkTests.promptStore.saved")
        defer { defaults.removePersistentDomain(forName: "VoiceInkTests.promptStore.saved") }
        let savedPrompt = CustomPrompt(title: "Saved", promptText: "Use this saved prompt.")
        let data = try JSONEncoder().encode([savedPrompt])
        defaults.set(data, forKey: EnhancementPromptStore.userDefaultsKey)

        let prompts = EnhancementPromptStore.loadPrompts(from: defaults)

        #expect(prompts == [savedPrompt])
    }

    @Test func transcriptionResultVariantsIncludeOriginalAndEnhancedText() {
        let transcription = Transcription(
            text: "raw dictated text",
            duration: 12,
            enhancedText: "Polished dictated text.",
            transcriptionStatus: .completed
        )

        let variants = TranscriptionResultVariant.variants(for: transcription)

        #expect(variants.count == 2)
        #expect(variants[0].tab == .original)
        #expect(variants[0].text == "raw dictated text")
        #expect(variants[1].tab == .enhanced)
        #expect(variants[1].text == "Polished dictated text.")
    }

    @Test func transcriptionResultVariantsSkipBlankEnhancedText() {
        let transcription = Transcription(
            text: "raw dictated text",
            duration: 12,
            enhancedText: "   ",
            transcriptionStatus: .completed
        )

        let variants = TranscriptionResultVariant.variants(for: transcription)

        #expect(variants.count == 1)
        #expect(variants.first?.tab == .original)
    }

    @Test func cloudTranscriptionTimeoutDefaultsToLongerRequestWindow() throws {
        let defaults = try #require(UserDefaults(suiteName: "VoiceInkTests.timeout.default"))
        defaults.removePersistentDomain(forName: "VoiceInkTests.timeout.default")

        #expect(TranscriptionRequestTimeout.seconds(in: defaults) == 300)
    }

    @Test func cloudTranscriptionTimeoutUsesUserSettingWithinBounds() throws {
        let defaults = try #require(UserDefaults(suiteName: "VoiceInkTests.timeout.custom"))
        defaults.removePersistentDomain(forName: "VoiceInkTests.timeout.custom")
        defer { defaults.removePersistentDomain(forName: "VoiceInkTests.timeout.custom") }

        defaults.set(600, forKey: TranscriptionRequestTimeout.userDefaultsKey)
        #expect(TranscriptionRequestTimeout.seconds(in: defaults) == 600)

        defaults.set(5, forKey: TranscriptionRequestTimeout.userDefaultsKey)
        #expect(TranscriptionRequestTimeout.seconds(in: defaults) == 30)

        defaults.set(5_000, forKey: TranscriptionRequestTimeout.userDefaultsKey)
        #expect(TranscriptionRequestTimeout.seconds(in: defaults) == 1_200)
    }

    @Test func dashboardInsightsUnlockProgressTracksRemainingDuration() {
        let lockedProgress = DashboardInsightsUnlockProgress(
            currentDuration: 12 * 60,
            requiredDuration: 30 * 60
        )

        #expect(lockedProgress.isUnlocked == false)
        #expect(abs(lockedProgress.fraction - 0.4) < 0.001)
        #expect(lockedProgress.remainingDuration == 18 * 60)

        let unlockedProgress = DashboardInsightsUnlockProgress(
            currentDuration: 45 * 60,
            requiredDuration: 30 * 60
        )

        #expect(unlockedProgress.isUnlocked == true)
        #expect(unlockedProgress.fraction == 1)
        #expect(unlockedProgress.remainingDuration == 0)
    }

    @Test func transcriptionTimingSummaryCalculatesSingleRecordingStats() {
        let text = Array(repeating: "word", count: 200).joined(separator: " ")
        let transcription = Transcription(
            text: text,
            duration: 120,
            transcriptionModelName: "Whisper Large",
            transcriptionDuration: 8,
            enhancementDuration: 2,
            transcriptionStatus: .completed
        )

        let summary = TranscriptionTimingSummary(transcription: transcription)

        #expect(summary.wordCount == 200)
        #expect(summary.audioDuration == 120)
        #expect(summary.wordsPerMinute == 100)
        #expect(abs(summary.productivityMultiplier - 2.5) < 0.001)
        #expect(summary.timeSaved == 180)
        #expect(summary.transcriptionSpeedFactor == 15)
        #expect(summary.totalProcessingDuration == 10)
    }

}
