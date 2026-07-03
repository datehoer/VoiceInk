import SwiftUI

enum TranscriptionTab: String, CaseIterable {
    case original = "Original"
    case enhanced = "Enhanced"
}

struct TranscriptionResultVariant: Identifiable, Equatable {
    let tab: TranscriptionTab
    let text: String

    var id: TranscriptionTab { tab }
    var label: LocalizedStringKey { LocalizedStringKey(tab.rawValue) }
    var isEnhanced: Bool { tab == .enhanced }

    static func variants(for transcription: Transcription) -> [TranscriptionResultVariant] {
        var variants = [
            TranscriptionResultVariant(tab: .original, text: transcription.text)
        ]

        if let enhancedText = transcription.enhancedText,
           !enhancedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            variants.append(TranscriptionResultVariant(tab: .enhanced, text: enhancedText))
        }

        return variants
    }

    static func preferredCopyText(for transcription: Transcription) -> String {
        variants(for: transcription).last?.text ?? transcription.text
    }
}
