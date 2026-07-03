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
    @AppStorage(TranscriptionPromptSettings.userDefaultsKey) private var storedPrompt = ""
    @AppStorage("SelectedLanguage") private var selectedLanguage = "en"

    var body: some View {
        Section {
            ZStack(alignment: .topLeading) {
                TextEditor(text: promptBinding)
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

                if activePrompt.isEmpty {
                    Text("Add words, names, formatting hints, or domain context")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                if isUsingDefaultPrompt {
                    Label("Using default preset", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use Default") {
                    savePrompt("")
                }
                .disabled(isUsingDefaultPrompt)
            }
        } header: {
            HStack(spacing: 4) {
                Text("Transcription Prompt")
                InfoTip("Applies to every transcription model path that accepts prompt guidance. If you leave it on the preset, VoiceInk still sends the default prompt.")
            }
        }
    }

    private var activePrompt: String {
        TranscriptionPromptSettings.promptOrDefault(storedPrompt)
    }

    private var isUsingDefaultPrompt: Bool {
        TranscriptionPromptSettings.isDefaultSelection(storedPrompt)
    }

    private var promptBinding: Binding<String> {
        Binding(
            get: { activePrompt },
            set: { newValue in
                savePrompt(newValue)
            }
        )
    }

    private func savePrompt(_ prompt: String) {
        TranscriptionPromptSettings.saveCustomPrompt(prompt, for: selectedLanguage)
    }
}

private struct EnhancementModelSettingsView: View {
    @EnvironmentObject private var aiService: AIService

    @AppStorage(DefaultEnhancementSettings.isEnabledKey) private var isDefaultEnhancementEnabled = true
    @AppStorage(DefaultEnhancementSettings.providerKey) private var defaultEnhancementProvider = ""
    @AppStorage(DefaultEnhancementSettings.modelKey) private var defaultEnhancementModel = ""
    @AppStorage("SkipShortEnhancement") private var isSkipShortEnhancementEnabled = true
    @AppStorage("ShortEnhancementWordThreshold") private var shortEnhancementWordThreshold = 3
    @AppStorage("EnhancementTimeoutSeconds") private var enhancementTimeoutSeconds = 7
    @AppStorage("EnhancementRetryOnTimeout") private var retryOnTimeout = true
    @State private var isShortEnhancementExpanded = false

    var body: some View {
        Form {
            Section {
                Toggle("Enhance transcriptions by default", isOn: $isDefaultEnhancementEnabled)

                if isDefaultEnhancementEnabled {
                    if providerOptions.isEmpty {
                        LabeledContent("Default provider") {
                            Text("No providers connected")
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    } else {
                        Picker("Default provider", selection: providerBinding) {
                            ForEach(providerOptions, id: \.self) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }

                        if let provider = selectedDefaultProvider {
                            defaultModelPicker(for: provider)
                        }
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Default Enhancement")
                    InfoTip("Applies when no mode is selected. A mode's own enhancement setting and model still take priority.")
                }
            }

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
        .onAppear(perform: ensureValidDefaultSelection)
        .onChange(of: isDefaultEnhancementEnabled) { _, _ in
            postSettingsChanged()
        }
        .onChange(of: aiService.connectedProviders) { _, _ in
            ensureValidDefaultSelection()
        }
    }

    private var providerOptions: [AIProvider] {
        aiService.connectedProviders
    }

    private var selectedDefaultProvider: AIProvider? {
        if let provider = AIProvider(rawValue: defaultEnhancementProvider),
           providerOptions.contains(provider) {
            return provider
        }

        return providerOptions.first
    }

    private var providerBinding: Binding<AIProvider> {
        Binding(
            get: { selectedDefaultProvider ?? providerOptions.first ?? .gemini },
            set: { provider in
                defaultEnhancementProvider = provider.rawValue
                defaultEnhancementModel = defaultModelSelection(for: provider)
                if provider == .ollama {
                    aiService.refreshOllamaAvailabilityInBackground()
                }
                postSettingsChanged()
            }
        )
    }

    @ViewBuilder
    private func defaultModelPicker(for provider: AIProvider) -> some View {
        if provider == .localCLI {
            LabeledContent("Default model") {
                Text("Default")
                    .foregroundStyle(.secondary)
            }
            .onAppear {
                if !defaultEnhancementModel.isEmpty {
                    defaultEnhancementModel = ""
                    postSettingsChanged()
                }
            }
        } else {
            let models = modelOptions(for: provider)

            if models.isEmpty {
                LabeledContent("Default model") {
                    Text(provider == .openRouter ? LocalizedStringKey("No models loaded") : LocalizedStringKey("No models available"))
                        .foregroundStyle(.secondary)
                        .italic()
                }
            } else {
                Picker("Default model", selection: modelBinding(for: provider)) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }

            if provider == .openRouter {
                Button("Refresh Models") {
                    Task { await aiService.fetchOpenRouterModels() }
                }
                .help("Refresh models")
            } else if provider == .ollama {
                Button("Refresh Models") {
                    aiService.refreshOllamaAvailabilityInBackground()
                }
                .disabled(aiService.isOllamaRefreshing)
                .help("Refresh models")
            }
        }
    }

    private func modelBinding(for provider: AIProvider) -> Binding<String> {
        Binding(
            get: { defaultModelSelection(for: provider) },
            set: { model in
                defaultEnhancementModel = model
                postSettingsChanged()
            }
        )
    }

    private func modelOptions(for provider: AIProvider) -> [String] {
        var models = aiService.availableModels(for: provider)
        let selectedModel = defaultModelSelection(for: provider)

        if !selectedModel.isEmpty,
           !models.contains(selectedModel) {
            models.insert(selectedModel, at: 0)
        }

        return models
    }

    private func defaultModelSelection(for provider: AIProvider) -> String {
        guard provider != .localCLI else { return "" }

        return DefaultEnhancementSettings.resolvedModelName(
            configuredModelName: defaultEnhancementModel,
            availableModels: aiService.availableModels(for: provider),
            selectedModel: aiService.selectedModel(for: provider),
            providerDefaultModel: provider.defaultModel
        )
    }

    private func ensureValidDefaultSelection() {
        guard let provider = selectedDefaultProvider else { return }

        var didChange = false
        if defaultEnhancementProvider != provider.rawValue {
            defaultEnhancementProvider = provider.rawValue
            didChange = true
        }

        let model = defaultModelSelection(for: provider)
        if defaultEnhancementModel != model {
            defaultEnhancementModel = model
            didChange = true
        }

        if didChange {
            postSettingsChanged()
        }
    }

    private func postSettingsChanged() {
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
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
