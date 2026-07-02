import Foundation
import SwiftUI

enum DashboardHeroHeadline {
    case calculatingProgress
    case startRecordingProgress
    case savedTime(String)
}

struct DashboardHeroCard: View {
    private static let headlineFont: Font = .system(size: 23, weight: .bold, design: .rounded)
    private static let highlightedHeadlineFont: Font = .system(size: 30, weight: .black, design: .rounded)

    let isLocked: Bool
    let headline: DashboardHeroHeadline
    let subtext: String
    let actionTitle: LocalizedStringKey
    let actionIcon: String
    let canViewInsights: Bool
    let unlockProgress: DashboardInsightsUnlockProgress
    let actionHelp: String
    let actionAccessibilityLabel: String
    let onViewInsights: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLocked {
                lockedInsightsPrompt
            } else {
                heroCopy
            }

            HStack(spacing: 12) {
                Button(action: onViewInsights) {
                    DashboardMomentumActionLabel(
                        title: actionTitle,
                        icon: actionIcon,
                        isPrimary: canViewInsights,
                        isLocked: !canViewInsights
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canViewInsights)
                .help(actionHelp)
                .accessibilityLabel(Text(actionAccessibilityLabel))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .background(DashboardImpactBackground(isLocked: isLocked))
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous))
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            headlineText
                .frame(maxWidth: 720, alignment: .leading)

            Text(subtext)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DashboardMomentumBackground.subtext)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }

    private var headlineText: Text {
        Text(styledHeadline)
    }

    private var styledHeadline: AttributedString {
        let highlightedValue: String
        var text: AttributedString

        switch headline {
        case .calculatingProgress:
            highlightedValue = String(localized: "VoiceInk progress")
            text = AttributedString(localized: "Calculating \(highlightedValue).")
        case .startRecordingProgress:
            highlightedValue = String(localized: "VoiceInk progress")
            text = AttributedString(localized: "Start recording to build \(highlightedValue).")
        case .savedTime(let value):
            highlightedValue = value
            text = AttributedString(localized: "You have saved \(highlightedValue) with VoiceInk")
        }

        text.font = Self.headlineFont
        text.foregroundColor = DashboardMomentumBackground.headline

        if let highlightedRange = text.range(of: highlightedValue) {
            text[highlightedRange].font = Self.highlightedHeadlineFont
            text[highlightedRange].foregroundColor = DashboardMomentumBackground.accent
        }

        return text
    }

    private var lockedInsightsPrompt: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.78))

                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DashboardMomentumBackground.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 8) {
                Text("Unlock stats and insights")
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(DashboardMomentumBackground.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(unlockProgressCaption)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DashboardMomentumBackground.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                DashboardInsightsUnlockProgressBar(progress: unlockProgress)
                    .frame(maxWidth: 420)
            }
            .frame(maxWidth: 540, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unlockProgressCaption: String {
        String(
            localized: "\(Formatters.formattedCompactHoursAndMinutes(unlockProgress.remainingDuration)) remaining to reach \(Formatters.formattedCompactHoursAndMinutes(unlockProgress.requiredDuration))."
        )
    }
}

private struct DashboardInsightsUnlockProgressBar: View {
    let progress: DashboardInsightsUnlockProgress

    private var completedText: String {
        Formatters.formattedCompactHoursAndMinutes(progress.completedDuration)
    }

    private var requiredText: String {
        Formatters.formattedCompactHoursAndMinutes(progress.requiredDuration)
    }

    private var percentText: String {
        "\(Int((progress.fraction * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.68))

                    Capsule(style: .continuous)
                        .fill(DashboardMomentumBackground.accent)
                        .frame(width: progress.fraction > 0 ? max(8, geometry.size.width * progress.fraction) : 0)
                }
            }
            .frame(height: 8)

            HStack(spacing: 8) {
                Text("\(completedText) / \(requiredText)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardMomentumBackground.headline)

                Spacer(minLength: 8)

                Text(percentText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardMomentumBackground.subtext)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Insights unlock progress")
        .accessibilityValue("\(completedText) of \(requiredText), \(percentText)")
    }
}

private struct DashboardMomentumActionLabel: View {
    private static let cornerRadius: CGFloat = 12

    let title: LocalizedStringKey
    let icon: String
    let isPrimary: Bool
    var isLocked = false

    var body: some View {
        HStack(spacing: 9) {
            Text(title)
                .lineLimit(2)

            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 18)
        .frame(minHeight: 40)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 5, y: 2)
    }

    private var foregroundColor: Color {
        if isPrimary {
            return Color.white
        }

        return isLocked ? DashboardMomentumBackground.subtext : AppTheme.Text.primary
    }

    private var backgroundColor: Color {
        if isPrimary {
            return DashboardMomentumBackground.accent
        }

        return isLocked ? Color.white.opacity(0.64) : Color.white.opacity(0.82)
    }

    private var borderColor: Color {
        if isPrimary {
            return Color.clear
        }

        return isLocked ? DashboardMomentumBackground.accent.opacity(0.22) : Color.black.opacity(0.08)
    }

    private var shadowColor: Color {
        isPrimary ? DashboardMomentumBackground.accent.opacity(0.18) : Color.black.opacity(0.06)
    }
}

private struct DashboardImpactBackground: View {
    var isLocked = false

    var body: some View {
        ZStack {
            Image("momentum-hero-bg")
                .resizable()
                .scaledToFill()
                .blur(radius: isLocked ? 2.5 : 0)
                .saturation(isLocked ? 0.78 : 1)

            if isLocked {
                Color.white.opacity(0.32)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous)
                .stroke(AppTheme.Border.card, lineWidth: 1)
        )
    }
}

private struct DashboardMomentumBackground {
    static let accent = Color(red: 0.76, green: 0.31, blue: 0.08)
    static let headline = Color(red: 0.10, green: 0.08, blue: 0.06)
    static let subtext = Color(red: 0.40, green: 0.34, blue: 0.28)
}
