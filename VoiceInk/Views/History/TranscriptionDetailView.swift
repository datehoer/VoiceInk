import SwiftUI

struct TranscriptionDetailView: View {
    let transcription: Transcription
    var onInfoTap: (() -> Void)?
    var onAnalyzeTap: (() -> Void)?

    private var hasAudioFile: Bool {
        if let urlString = transcription.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()

                Button(action: { onAnalyzeTap?() }) {
                    Label("Analyze", systemImage: "chart.bar.xaxis")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(AppCardBackground(cornerRadius: 15))
                .help("Analyze timing")
            }
            .padding(.horizontal, 16)

            ScrollView {
                TranscriptionResultStack(transcription: transcription)
                .padding(16)
            }

            if hasAudioFile, let urlString = transcription.audioFileURL,
               let url = URL(string: urlString) {
                VStack(spacing: 0) {
                    Divider()

                    AudioPlayerView(url: url, transcription: transcription, onInfoTap: onInfoTap)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                .fill(AppTheme.Surface.materialCard)
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                        .strokeBorder(AppTheme.Border.card, lineWidth: 1)
                                }
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

struct TranscriptionTimingPanel: View {
    let transcription: Transcription
    let onClose: () -> Void

    private var summary: TranscriptionTimingSummary {
        TranscriptionTimingSummary(transcription: transcription)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppPanelHeader(title: "Analyze", onClose: onClose)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryGrid
                    timingSection
                    modelSection
                }
                .padding(16)
            }
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            timingMetricTile(
                icon: "text.word.spacing",
                value: Formatters.formattedNumber(summary.wordCount),
                label: "Words",
                color: AppTheme.Data.transcript
            )
            timingMetricTile(
                icon: "speedometer",
                value: summary.hasTimingData ? String(localized: "\(summary.wordsPerMinute) WPM") : "--",
                label: "Average WPM",
                color: AppTheme.Data.audio
            )
            timingMetricTile(
                icon: "clock.badge.checkmark",
                value: summary.hasTimingData ? Formatters.formattedCompactHoursAndMinutes(summary.timeSaved) : "--",
                label: "Time saved",
                color: AppTheme.Data.enhancement
            )
            timingMetricTile(
                icon: "bolt.fill",
                value: summary.hasTimingData ? Self.formattedMultiplier(summary.productivityMultiplier) : "--",
                label: "Productivity",
                color: AppTheme.Sidebar.license
            )
        }
    }

    private func timingMetricTile(icon: String, value: String, label: LocalizedStringKey, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DashboardIconGlyph(systemName: icon, color: color, size: 13, frameSize: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .background(MetricTintBackground(color: color))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Timing")

            VStack(spacing: 0) {
                timingRow(label: "Dictation duration", value: Formatters.formattedPreciseDuration(summary.audioDuration))
                Divider().padding(.horizontal, 12)
                timingRow(label: "Transcription time", value: formattedOptionalDuration(summary.transcriptionDuration))
                Divider().padding(.horizontal, 12)
                timingRow(label: "Enhancement time", value: formattedOptionalDuration(summary.enhancementDuration))
                Divider().padding(.horizontal, 12)
                timingRow(label: "Total processing", value: Formatters.formattedPreciseDuration(summary.totalProcessingDuration))
                Divider().padding(.horizontal, 12)
                timingRow(label: "Transcription speed", value: Self.formattedRealtimeFactor(summary.transcriptionSpeedFactor))
            }
            .background(AppCardBackground(cornerRadius: 12))
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Models")

            VStack(spacing: 0) {
                timingRow(label: "Transcription model", value: sanitized(transcription.transcriptionModelName) ?? "-")

                if sanitized(transcription.aiEnhancementModelName) != nil {
                    Divider().padding(.horizontal, 12)
                    timingRow(label: "Enhancement model", value: sanitized(transcription.aiEnhancementModelName) ?? "-")
                }

                if sanitized(transcription.modeName) != nil {
                    Divider().padding(.horizontal, 12)
                    timingRow(label: "Mode", value: sanitized(transcription.modeName) ?? "-")
                }
            }
            .background(AppCardBackground(cornerRadius: 12))
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.Text.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func timingRow(label: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func formattedOptionalDuration(_ duration: TimeInterval?) -> String {
        guard let duration else {
            return "-"
        }

        return Formatters.formattedPreciseDuration(duration)
    }

    private func sanitized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func formattedMultiplier(_ value: Double) -> String {
        guard value > 0 else {
            return "--"
        }

        return String(format: String(localized: "%.1fx faster"), value)
    }

    private static func formattedRealtimeFactor(_ value: Double) -> String {
        guard value > 0 else {
            return "-"
        }

        return String(format: String(localized: "%.1fx real-time"), value)
    }
}
