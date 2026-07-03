import Foundation

enum StarterModeKind: String, CaseIterable, Identifiable {
    case clean
    case enhance
    case email
    case rewrite
    case assistant

    var id: String { rawValue }
}

struct StarterModeTemplate: Identifiable {
    let kind: StarterModeKind
    let id: UUID
    let name: String
    let icon: ModeIcon
    let description: String
    let guidance: String
    let promptId: UUID?
    let outputMode: ModeOutputMode
    let usesAIEnhancement: Bool
    let useSelectedTextContext: Bool
    let useScreenCapture: Bool
    let isDefault: Bool

    var featureLabels: [String] {
        var labels = ["Transcription", "Realtime"]

        if usesAIEnhancement {
            labels.append("AI")
        } else {
            labels.append("No AI")
        }

        if outputMode == .respond {
            labels.append("Respond")
        } else {
            labels.append("Paste")
        }

        return labels
    }
}

enum StarterModeCatalog {
    static let cleanModeID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let enhancementModeID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!

    static let templates: [StarterModeTemplate] = [
        StarterModeTemplate(
            kind: .clean,
            id: cleanModeID,
            name: "Dictation",
            icon: .symbol("mic.fill"),
            description: String(localized: "Fast transcription with no AI enhancement."),
            guidance: String(localized: "Use this when you want the quickest possible voice-to-text result. It records with your configured transcription model and pastes the transcript as-is."),
            promptId: nil,
            outputMode: .paste,
            usesAIEnhancement: false,
            useSelectedTextContext: false,
            useScreenCapture: false,
            isDefault: true
        ),
        StarterModeTemplate(
            kind: .enhance,
            id: enhancementModeID,
            name: "Enhancement",
            icon: .symbol("sparkles"),
            description: "Clean up dictated text while preserving your meaning.",
            guidance: "Use this for everyday writing when you want grammar, flow, and light formatting improved before the result is pasted.",
            promptId: PromptTemplates.defaultPromptId,
            outputMode: .paste,
            usesAIEnhancement: true,
            useSelectedTextContext: true,
            useScreenCapture: true,
            isDefault: false
        ),
        StarterModeTemplate(
            kind: .email,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            name: "Email",
            icon: .symbol("envelope.fill"),
            description: "Turn a rough thought into a clean email.",
            guidance: "Use this after selecting relevant text or opening the related window. VoiceInk uses that context to shape a clear email draft.",
            promptId: PromptTemplates.emailPromptId,
            outputMode: .paste,
            usesAIEnhancement: true,
            useSelectedTextContext: true,
            useScreenCapture: true,
            isDefault: false
        ),
        StarterModeTemplate(
            kind: .rewrite,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            name: "Rewrite",
            icon: .symbol("quote.bubble.fill"),
            description: "Rewrite selected or dictated text with better clarity.",
            guidance: "Use this when you have text selected and want a stronger version. The selected text is available as context for the rewrite.",
            promptId: PromptTemplates.rewritePromptId,
            outputMode: .paste,
            usesAIEnhancement: true,
            useSelectedTextContext: true,
            useScreenCapture: false,
            isDefault: false
        ),
        StarterModeTemplate(
            kind: .assistant,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
            name: "Assistant",
            icon: .symbol("bubble.left.and.bubble.right.fill"),
            description: "Ask a question and keep the answer in the recorder.",
            guidance: "Use this for answers, summaries, and follow-ups. Instead of pasting, VoiceInk keeps the conversation inside the recorder.",
            promptId: PromptTemplates.assistantPromptId,
            outputMode: .respond,
            usesAIEnhancement: true,
            useSelectedTextContext: false,
            useScreenCapture: false,
            isDefault: false
        )
    ]

    static var ids: Set<UUID> {
        Set(templates.map(\.id))
    }
}

enum StarterModeDefaultPolicy {
    static func defaultKind(for kinds: Set<StarterModeKind>) -> StarterModeKind? {
        if kinds.contains(.enhance) {
            return .enhance
        }

        if kinds.contains(.clean) {
            return .clean
        }

        return StarterModeCatalog.templates.first { kinds.contains($0.kind) }?.kind
    }

    static func defaultTemplateID(for kinds: Set<StarterModeKind>) -> UUID? {
        guard let defaultKind = defaultKind(for: kinds) else { return nil }
        return StarterModeCatalog.templates.first { $0.kind == defaultKind }?.id
    }
}
