import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = SettingsTab.models

    enum SettingsTab: Hashable {
        case models, profile, general
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AnalysisSettingsTab()
                .tabItem { Label("Models", systemImage: "brain") }
                .tag(SettingsTab.models)

            ProfileSettingsTab()
                .tabItem { Label("Profile", systemImage: "person.text.rectangle") }
                .tag(SettingsTab.profile)

            ScanningSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
        }
        .frame(width: 480, height: tabHeight)
        .fixedSize()
    }

    /// Each tab sized to its content; the window follows on tab switch.
    private var tabHeight: CGFloat {
        switch selectedTab {
        case .models: return 430
        case .profile: return 300
        case .general: return 290
        }
    }
}

// MARK: - Analysis Tab

struct AnalysisSettingsTab: View {
    @AppStorage(AnalysisProviderKind.storageKey) private var providerRaw = AnalysisProviderKind.ollama.rawValue
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = "http://localhost:11434"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage("ollamaApiKey") private var ollamaApiKey = ""
    @AppStorage("anthropicApiKey") private var anthropicApiKey = ""
    @AppStorage("anthropicModel") private var anthropicModel = "claude-3-5-haiku-latest"
    @AppStorage("openAIApiKey") private var openAIApiKey = ""
    @AppStorage("openAIModel") private var openAIModel = "gpt-4o-mini"
    @AppStorage("appleIntelligenceModel") private var appleIntelligenceModel = "system-language-model"
    @AppStorage("appleIntelligenceUsePCC") private var appleIntelligenceUsePCC = true
    @AppStorage("appleIntelligenceStyleNotes") private var appleIntelligenceStyleNotes = ""

    @State private var availableModels: [String] = []
    @State private var fetchState: FetchState = .idle
    @State private var pccStatus: String? = nil
    @State private var advancedExpanded = false
    @State private var didInitAdvanced = false

    enum FetchState { case idle, loading, loaded, failed(String) }

    enum ProviderTestStatus {
        case idle(String)
        case testing(String)
        case success(String)
        case failure(String)
    }

    private var provider: AnalysisProviderKind {
        AnalysisProviderKind(rawValue: providerRaw) ?? .ollama
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionTitle(provider.displayName)
            SettingsCard {
                switch provider {
                case .ollama:
                    ollamaConfig
                case .anthropic:
                    cloudConfig(apiKey: $anthropicApiKey, model: $anthropicModel,
                                hint: "Anthropic API key (console.anthropic.com). Stored in app preferences.")
                case .openAI:
                    cloudConfig(apiKey: $openAIApiKey, model: $openAIModel,
                                hint: "OpenAI API key (platform.openai.com). Stored in app preferences.")
                case .appleIntelligence:
                    appleIntelligenceConfig
                }
            }

            DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                HStack {
                    Text("Engine")
                        .frame(width: 64, alignment: .leading)
                    Spacer()
                    Picker("", selection: $providerRaw) {
                        ForEach(AnalysisProviderKind.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 190)
                }
                SettingsFooter("Use a different engine — a local Ollama server or a cloud API.")
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .controlSize(.small)
        .task(id: providerRaw) {
            availableModels = []
            fetchState = .idle
            await fetchModels()
        }
        .onAppear {
            if !didInitAdvanced {
                advancedExpanded = (provider != .appleIntelligence)
                didInitAdvanced = true
            }
        }
    }

    @ViewBuilder
    private var ollamaConfig: some View {
        HStack {
            Text("Base URL")
                .frame(width: 64, alignment: .leading)
            TextField("Base URL", text: $ollamaBaseURL)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            fetchButton
        }

        Divider()

        HStack {
            Text("API Key")
                .frame(width: 64, alignment: .leading)
            SecureField("Optional — for ollama.com cloud models", text: $ollamaApiKey)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
        }

        SettingsFooter("Leave blank for a local Ollama server. Add an ollama.com key (and set the Base URL to https://ollama.com) to use cloud models.")

        Divider()
        ProviderStatusView(status: providerStatus)
        Divider()
        modelRow(model: $ollamaModel)
    }

    @ViewBuilder
    private func cloudConfig(apiKey: Binding<String>, model: Binding<String>, hint: String) -> some View {
        HStack {
            Text("API Key")
                .frame(width: 64, alignment: .leading)
            SecureField("Paste API key", text: apiKey)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            fetchButton
        }

        SettingsFooter(hint)

        Divider()
        ProviderStatusView(status: providerStatus)
        Divider()
        modelRow(model: model)
    }

    @ViewBuilder
    private var appleIntelligenceConfig: some View {
        HStack {
            Text("Status")
                .frame(width: 64, alignment: .leading)
            ProviderStatusView(status: providerStatus)
            fetchButton
        }

        SettingsFooter("On-device Foundation Models. No API key — analysis never leaves this Mac. Requires macOS 26+ with Apple Intelligence enabled.")

        Divider()

        Toggle("Use Private Cloud Compute when available", isOn: $appleIntelligenceUsePCC)

        SettingsFooter("macOS 27+: runs analysis on Apple's private servers for much higher quality. Falls back to the on-device model when offline or over quota.")

        if appleIntelligenceUsePCC, let pccStatus {
            SettingsFooter(pccStatus)
        }

        Divider()

        HStack(alignment: .top) {
            Text("Style")
                .frame(width: 64, alignment: .leading)
            TextField("e.g. Mention alternatives. Keep best-use under 12 words.", text: $appleIntelligenceStyleNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .controlSize(.small)
        }

        SettingsFooter("Appended to the analysis instructions. Experiment freely — applies to the next re-analyze.")
    }

    private var fetchButton: some View {
        Button {
            Task { await fetchModels() }
        } label: {
            switch fetchState {
            case .loading:
                ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
            case .loaded:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .idle:
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(.borderless)
        .help("Test connection and fetch models")
    }

    @ViewBuilder
    private func modelRow(model: Binding<String>) -> some View {
        if availableModels.isEmpty {
            HStack {
                Text("Model")
                    .frame(width: 64, alignment: .leading)
                TextField("Model name", text: model)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button("Fetch") {
                    Task { await fetchModels() }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        } else {
            HStack {
                Text("Model")
                    .frame(width: 64, alignment: .leading)
                Spacer()
                Picker("", selection: model) {
                    ForEach(availableModels, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }
        }
    }

    private var providerStatus: ProviderTestStatus {
        switch fetchState {
        case .idle:
            return .idle("Not tested")
        case .loading:
            return .testing("Testing \(provider.displayName)…")
        case .loaded:
            if provider == .appleIntelligence {
                return .success("Available on this Mac")
            }
            let count = availableModels.count
            return count == 0 ? .success("Connected. No models found.") : .success("Connected. \(count) model(s).")
        case .failed(let message):
            return .failure(message)
        }
    }

    private func fetchModels() async {
        fetchState = .loading
        let result: ModelFetchResult
        switch provider {
        case .ollama: result = await OllamaService().fetchModels()
        case .anthropic: result = await AnthropicService().fetchModels()
        case .openAI: result = await OpenAIService().fetchModels()
        case .appleIntelligence: result = await AppleIntelligenceService().fetchModels()
        }
        switch result {
        case .models(let models):
            availableModels = models
            // Auto-select the first model if the current selection isn't available.
            let key = provider.modelDefaultsKey
            let current = UserDefaults.standard.string(forKey: key) ?? ""
            if !models.contains(current), let first = models.first {
                UserDefaults.standard.set(first, forKey: key)
            }
            fetchState = .loaded
        case .failure(let message):
            availableModels = []
            fetchState = .failed(message)
        }

        if provider == .appleIntelligence {
            pccStatus = appleIntelligenceUsePCC ? await AppleIntelligenceService().probePrivateCloudCompute() : nil
        } else {
            pccStatus = nil
        }
    }
}

// MARK: - Profile Tab

struct ProfileSettingsTab: View {
    @AppStorage(WorkflowProfile.storageKey) private var profileText = ""
    @AppStorage("lastProfileDigest") private var lastProfileDigest = ""

    var body: some View {
        Form {
            Section("Automatic profile") {
                SettingsFooter(lastProfileDigest.isEmpty
                    ? "Derived from your installed apps after the first scan — categories, recently used, and open apps."
                    : lastProfileDigest)
            }

            Section("Custom override") {
                TextEditor(text: $profileText)
                    .font(.body)
                    .frame(minHeight: 58)
                    .scrollContentBackground(.hidden)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))

                SettingsFooter("Leave empty to use the automatic profile. Re-analyze an app to apply changes.")
            }

            Section {
                Button("Clear Override") { profileText = "" }
                    .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
    }
}

// MARK: - Scanning Tab

struct ScanningSettingsTab: View {
    @AppStorage("includeAppleApps") private var includeAppleApps = false
    @AppStorage("includeUtilityApps") private var includeUtilityApps = true
    @AppStorage("appearancePreference") private var appearancePreference = "system"
    @AppStorage("defaultLicenseEmail") private var defaultLicenseEmail = ""

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearancePreference) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Licenses") {
                TextField("Default email for new license keys", text: $defaultLicenseEmail)
                    .textFieldStyle(.roundedBorder)

                SettingsFooter("Prefilled when you save a license key. Change it per key when an app is registered to a different account.")
            }

            Section("Directories") {
                Toggle("Include /Applications/Utilities", isOn: $includeUtilityApps)
                Toggle("Include Apple system apps (com.apple.*)", isOn: $includeAppleApps)
                    .help("System apps can't be uninstalled — enabling adds noise to results")
            }

            Section {
                SettingsFooter("Changes take effect on the next rescan.")
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
    }
}

private struct SettingsFooter: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProviderStatusView: View {
    let status: AnalysisSettingsTab.ProviderTestStatus

    var body: some View {
        HStack(spacing: 6) {
            switch status {
            case .idle(let text):
                Image(systemName: "circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                SettingsFooter(text)
            case .testing(let text):
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 12, height: 12)
                SettingsFooter(text)
            case .success(let text):
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                SettingsFooter(text, color: .green)
            case .failure(let text):
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                SettingsFooter(text, color: .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
