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

    @Test func dashboardProductivityMetricsCalculateDictationStats() {
        let metrics = DashboardProductivityMetrics(
            totals: DashboardMetricTotals(
                count: 4,
                words: 1_580,
                duration: 600
            )
        )

        #expect(metrics.wordCount == 1_580)
        #expect(metrics.sessionCount == 4)
        #expect(metrics.totalDuration == 600)
        #expect(metrics.averageWordsPerMinute == 158)
        #expect(abs(metrics.productivityMultiplier - 3.95) < 0.001)
        #expect(metrics.timeSaved == 1_770)
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
