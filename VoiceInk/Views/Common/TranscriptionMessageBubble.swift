import SwiftUI

struct TranscriptionResultStack: View {
    let transcription: Transcription
    var maxBubbleHeight: CGFloat = 350
    var spacing: CGFloat = 16

    private var variants: [TranscriptionResultVariant] {
        TranscriptionResultVariant.variants(for: transcription)
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(variants) { variant in
                TranscriptionMessageBubble(
                    label: variant.label,
                    text: variant.text,
                    isEnhanced: variant.isEnhanced,
                    maxHeight: maxBubbleHeight
                )
            }
        }
    }
}

struct TranscriptionMessageBubble: View {
    let label: LocalizedStringKey
    let text: String
    let isEnhanced: Bool
    var maxHeight: CGFloat = 350

    var body: some View {
        HStack(alignment: .bottom) {
            if isEnhanced { Spacer(minLength: 60) }

            VStack(alignment: isEnhanced ? .leading : .trailing, spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(AppTheme.Text.muted)
                    .padding(.horizontal, 12)

                ScrollView {
                    MarkdownContentView(
                        text,
                        fontSize: 14,
                        foregroundColor: AppTheme.Text.primary,
                        alignment: isEnhanced ? .leading : .trailing
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: maxHeight)
                .background(background)
                .hoverCopyButton(textToCopy: text)
            }

            if !isEnhanced { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var background: some View {
        if isEnhanced {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.Surface.subtle)
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .strokeBorder(AppTheme.Border.tint, lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.Surface.materialCard)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .strokeBorder(AppTheme.Border.subtle, lineWidth: 1)
                )
        }
    }
}
