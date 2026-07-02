import Foundation
import SwiftData

enum TranscriptionStatus: String, Codable {
    case pending
    case completed
    case failed
    case canceled
}

@Model
final class Transcription {
    static let canceledTranscriptionText = "The transcription was canceled."

    var id: UUID = UUID()
    var text: String = ""
    var enhancedText: String?
    var timestamp: Date = Date()
    var duration: TimeInterval = 0
    var audioFileURL: String?
    var transcriptionModelName: String?
    var aiEnhancementModelName: String?
    var promptName: String?
    var transcriptionDuration: TimeInterval?
    var enhancementDuration: TimeInterval?
    var aiRequestSystemMessage: String?
    var aiRequestUserMessage: String?
    @Attribute(originalName: "powerModeName")
    var modeName: String?
    @Attribute(originalName: "powerModeEmoji")
    var modeEmoji: String?
    var transcriptionStatus: String?

    init(text: String,
         duration: TimeInterval,
         enhancedText: String? = nil,
         audioFileURL: String? = nil,
         transcriptionModelName: String? = nil,
         aiEnhancementModelName: String? = nil,
         promptName: String? = nil,
         transcriptionDuration: TimeInterval? = nil,
         enhancementDuration: TimeInterval? = nil,
         aiRequestSystemMessage: String? = nil,
         aiRequestUserMessage: String? = nil,
         modeName: String? = nil,
         modeEmoji: String? = nil,
         transcriptionStatus: TranscriptionStatus = .pending) {
        self.id = UUID()
        self.text = text
        self.enhancedText = enhancedText
        self.timestamp = Date()
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.promptName = promptName
        self.transcriptionDuration = transcriptionDuration
        self.enhancementDuration = enhancementDuration
        self.aiRequestSystemMessage = aiRequestSystemMessage
        self.aiRequestUserMessage = aiRequestUserMessage
        self.modeName = modeName
        self.modeEmoji = modeEmoji
        self.transcriptionStatus = transcriptionStatus.rawValue
    }

    func markAsCanceledTranscription(
        duration: TimeInterval? = nil,
        modelName: String? = nil
    ) {
        text = Self.canceledTranscriptionText
        enhancedText = nil
        transcriptionStatus = TranscriptionStatus.canceled.rawValue
        if let duration {
            self.duration = duration
        }
        if let modelName {
            transcriptionModelName = modelName
        }
        transcriptionDuration = nil
        enhancementDuration = nil
        aiEnhancementModelName = nil
        promptName = nil
        aiRequestSystemMessage = nil
        aiRequestUserMessage = nil
    }
}

struct TranscriptionTimingSummary: Equatable {
    let wordCount: Int
    let audioDuration: TimeInterval
    let transcriptionDuration: TimeInterval?
    let enhancementDuration: TimeInterval?
    let wordsPerMinute: Int
    let productivityMultiplier: Double
    let timeSaved: TimeInterval
    let transcriptionSpeedFactor: Double
    let totalProcessingDuration: TimeInterval

    init(transcription: Transcription) {
        let textForCounting = Self.finalTextForCounting(from: transcription)
        let audioDuration = max(transcription.duration, 0)
        let transcriptionDuration = transcription.transcriptionDuration.flatMap { $0 > 0 ? $0 : nil }
        let enhancementDuration = transcription.enhancementDuration.flatMap { $0 > 0 ? $0 : nil }
        let wordCount = WordCounter.count(in: textForCounting)

        self.wordCount = wordCount
        self.audioDuration = audioDuration
        self.transcriptionDuration = transcriptionDuration
        self.enhancementDuration = enhancementDuration
        self.wordsPerMinute = DashboardTimeSaving.wordsPerMinute(words: wordCount, duration: audioDuration)
        self.productivityMultiplier = DashboardTimeSaving.productivityMultiplier(words: wordCount, duration: audioDuration)
        self.timeSaved = DashboardTimeSaving.timeSaved(words: wordCount, duration: audioDuration)
        self.transcriptionSpeedFactor = {
            guard let transcriptionDuration, audioDuration > 0 else {
                return 0
            }
            return audioDuration / transcriptionDuration
        }()
        self.totalProcessingDuration = (transcriptionDuration ?? 0) + (enhancementDuration ?? 0)
    }

    var hasTimingData: Bool {
        audioDuration > 0 || transcriptionDuration != nil || enhancementDuration != nil
    }

    private static func finalTextForCounting(from transcription: Transcription) -> String {
        if let enhancedText = transcription.enhancedText,
           !enhancedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return enhancedText
        }

        return transcription.text
    }
}
