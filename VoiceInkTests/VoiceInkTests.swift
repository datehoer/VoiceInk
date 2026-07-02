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
                prompt: "Hello, how are you doing? Nice to meet you."
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
                (part["text"] as? String)?.contains("Hello, how are you doing? Nice to meet you.") == true
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
            customBodyTemplate: #"{"model":"{{model}}","messages":{{messages_json}}}"#
        )

        let stored = provider.normalizedForStorage

        #expect(stored.models == ["models/gemini-3.5-flash", "models/gemini-3.5-pro"])
        #expect(stored.selectedModel == "models/gemini-3.5-pro")
        #expect(stored.modelDiscoveryEndpoint == "https://api.example.com/v1/models")
        #expect(stored.customBodyTemplate == #"{"model":"{{model}}","messages":{{messages_json}}}"#)
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
