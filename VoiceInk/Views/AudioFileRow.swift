import SwiftUI

struct AudioFileRow: View {
    @ObservedObject var item: AudioFileQueueItem
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onRemove: () -> Void
    let onRetry: () -> Void

    private var actionText: String {
        guard let transcription = item.transcription else { return "" }
        return TranscriptionResultVariant.preferredCopyText(for: transcription)
    }

    var body: some View {
        switch item.status {
        case .pending:
            pendingRow
        case .processing(let phase):
            processingRow(phase: phase)
        case .completed:
            completedRows
        case .failed(let message):
            failedRow(message: message)
        }
    }

    // MARK: - Pending

    private var pendingRow: some View {
        HStack {
            Image(systemName: "clock")
                .foregroundColor(.secondary)

            Text(item.filename)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text("Waiting")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Processing

    private func processingRow(phase: QueueItemStatus.ProcessingPhase) -> some View {
        HStack {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)

            Text(item.filename)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(LocalizedStringKey(phase.rawValue))
                .font(.caption)
                .foregroundColor(AppTheme.Accent.primary)
        }
    }

    // MARK: - Completed

    @ViewBuilder
    private var completedRows: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppTheme.Status.positive)

            Text(item.filename)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !isExpanded, let transcription = item.transcription {
                Text(transcription.enhancedText ?? transcription.text)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let transcription = item.transcription {
                HStack(spacing: 2) {
                    CopyIconButton(textToCopy: actionText)
                    SaveIconButton(textToSave: actionText)
                }

                if transcription.duration > 0 {
                    Text(formatDuration(transcription.duration))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggleExpand() }

        if isExpanded, let transcription = item.transcription {
            TranscriptionResultStack(
                transcription: transcription,
                maxBubbleHeight: 260,
                spacing: 12
            )

            HStack(spacing: 12) {
                if let model = transcription.transcriptionModelName {
                    Label(model, systemImage: "cpu")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let prompt = transcription.promptName {
                    Label(prompt, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Failed

    private func failedRow(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(AppTheme.Status.error)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(message)
                    .font(.caption)
                    .foregroundColor(AppTheme.Status.error.opacity(0.80))
                    .lineLimit(2)
            }

            Spacer()

            Button {
                onRetry()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
