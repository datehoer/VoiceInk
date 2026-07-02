import SwiftUI

struct ModelSettingsPanel: View {
    @State private var selectedTab: ModelSettingsTab = .transcription

    var body: some View {
        VStack(spacing: 0) {
            ModelSettingsTabBar(selection: $selectedTab)

            switch selectedTab {
            case .transcription:
                TranscriptionModelSettingsView()
            case .enhancement:
                EnhancementModelSettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private enum ModelSettingsTab: String, CaseIterable, Identifiable {
    case transcription = "Transcription"
    case enhancement = "Enhancement"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .transcription:
            return "captions.bubble.fill"
        case .enhancement:
            return "sparkles"
        }
    }
}

private struct ModelSettingsTabBar: View {
    @Binding var selection: ModelSettingsTab

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ModelSettingsTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)

                        Text(LocalizedStringKey(tab.rawValue))
                            .font(.system(size: 14, weight: selection == tab ? .semibold : .medium))
                    }
                    .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        AppMaterialCardBackground(isSelected: selection == tab, cornerRadius: 22)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct TranscriptionModelSettingsView: View {
    @AppStorage(TranscriptionRequestTimeout.userDefaultsKey) private var transcriptionTimeoutSeconds = TranscriptionRequestTimeout.defaultSeconds

    var body: some View {
        Form {
            FillerWordsSettingsSection()

            TranscriptionPromptSettingsSection()

            Section {
                Stepper(
                    value: $transcriptionTimeoutSeconds,
                    in: TranscriptionRequestTimeout.minimumSeconds...TranscriptionRequestTimeout.maximumSeconds,
                    step: 30
                ) {
                    LabeledContent("Timeout duration") {
                        Text(formatDuration(transcriptionTimeoutSeconds))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Cloud Request Timeout")
                    InfoTip("Set how long VoiceInk waits for cloud transcription providers to respond before reporting a timeout.")
                }
            }

            AdvancedModelSettingsSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            transcriptionTimeoutSeconds = TranscriptionRequestTimeout.sanitize(transcriptionTimeoutSeconds)
        }
        .onChange(of: transcriptionTimeoutSeconds) { _, newValue in
            let sanitized = TranscriptionRequestTimeout.sanitize(newValue)
            if sanitized != newValue {
                transcriptionTimeoutSeconds = sanitized
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return String(format: String(localized: "%d seconds"), seconds)
        }

        let minutes = seconds / 60
        let remainder = seconds % 60
        if remainder == 0 {
            return String(format: String(localized: "%d minutes"), minutes)
        }
        return String(format: String(localized: "%d min %d sec"), minutes, remainder)
    }
}

private struct TranscriptionPromptSettingsSection: View {
    @AppStorage(TranscriptionPromptSettings.userDefaultsKey) private var transcriptionPrompt = ""
    @AppStorage("SelectedLanguage") private var selectedLanguage = "en"

    var body: some View {
        Section {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $transcriptionPrompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 92)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.Surface.control)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                            )
                    )

                if transcriptionPrompt.isEmpty {
                    Text("Add words, names, formatting hints, or domain context")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Spacer()
                Button("Clear Prompt") {
                    transcriptionPrompt = ""
                    savePrompt("")
                }
                .disabled(transcriptionPrompt.isEmpty)
            }
        } header: {
            HStack(spacing: 4) {
                Text("Transcription Prompt")
                InfoTip("Sent as guidance to local Whisper, OpenAI-compatible transcription, Gemini transcription, and custom transcription templates that use {{prompt}}.")
            }
        }
        .onChange(of: transcriptionPrompt) { _, newValue in
            savePrompt(newValue)
        }
    }

    private func savePrompt(_ prompt: String) {
        TranscriptionPromptSettings.saveCustomPrompt(prompt, for: selectedLanguage)
    }
}

private struct EnhancementModelSettingsView: View {
    @AppStorage("SkipShortEnhancement") private var isSkipShortEnhancementEnabled = true
    @AppStorage("ShortEnhancementWordThreshold") private var shortEnhancementWordThreshold = 3
    @AppStorage("EnhancementTimeoutSeconds") private var enhancementTimeoutSeconds = 7
    @AppStorage("EnhancementRetryOnTimeout") private var retryOnTimeout = true
    @State private var isShortEnhancementExpanded = false

    var body: some View {
        Form {
            Section {
                ExpandableSettingsRow(
                    isExpanded: $isShortEnhancementExpanded,
                    isEnabled: $isSkipShortEnhancementEnabled,
                    label: "Skip short transcriptions",
                    infoMessage: "Automatically skip AI enhancement when the transcription has very few words. Short phrases like \"yes\", \"thank you\", or quick commands don't benefit from enhancement."
                ) {
                    Picker("Minimum words", selection: $shortEnhancementWordThreshold) {
                        ForEach(1...15, id: \.self) { count in
                            Text(String(localized: "\(count) words")).tag(count)
                        }
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Enhancement Settings")
            }

            Section {
                Picker("Timeout duration", selection: $enhancementTimeoutSeconds) {
                    ForEach([3, 5, 7, 10, 15, 20, 30, 40, 50, 60], id: \.self) { seconds in
                        Text(String(format: String(localized: "%d seconds"), seconds)).tag(seconds)
                    }
                }
                .pickerStyle(.menu)

                Picker("On timeout", selection: $retryOnTimeout) {
                    Text("Fail immediately").tag(false)
                    Text("Retry").tag(true)
                }
                .pickerStyle(.menu)
            } header: {
                HStack(spacing: 4) {
                    Text("Request Timeout")
                    InfoTip("Set how long to wait for the AI provider to respond. If no response is received within this duration, you can either fail immediately and paste the original transcription, or retry the request up to 3 attempts.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AdvancedModelSettingsSection: View {
    @AppStorage("IsVADEnabled") private var isVADEnabled = true
    @AppStorage("AppendTrailingSpace") private var appendTrailingSpace = true
    @AppStorage("PrewarmModelOnWake") private var prewarmModelOnWake = true

    var body: some View {
        Section {
            Toggle(isOn: $appendTrailingSpace) {
                HStack(spacing: 4) {
                    Text("Add Space After Paste")
                    InfoTip("Add a trailing space after pasted transcription output.")
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: $isVADEnabled) {
                HStack(spacing: 4) {
                    Text("Voice Activity Detection (VAD)")
                    InfoTip("Detect speech segments and filter out silence to improve accuracy of local models.")
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: $prewarmModelOnWake) {
                HStack(spacing: 4) {
                    Text("Prewarm model (Experimental)")
                    InfoTip("Turn this on if transcriptions with local models are taking longer than expected. Runs silent background transcription on app launch and wake to trigger optimization.")
                }
            }
            .toggleStyle(.switch)
        } header: {
            Text("Advanced")
        }
    }
}
