import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AnalysisSettingsTab()
                .tabItem { Label("Models", systemImage: "brain") }

            ProfileSettingsTab()
                .tabItem { Label("Profile", systemImage: "person.text.rectangle") }

            ScanningSettingsTab()
                .tabItem { Label("Scanning", systemImage: "folder.badge.gearshape") }
        }
        .frame(width: 480, height: 340)
        .fixedSize()
    }
}

// MARK: - Analysis Tab

struct AnalysisSettingsTab: View {
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = "http://localhost:11434"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage("ollamaApiKey") private var ollamaApiKey = ""

    @State private var availableModels: [String] = []
    @State private var fetchState: FetchState = .idle

    enum FetchState { case idle, loading, loaded, failed(String) }

    enum ProviderTestStatus {
        case idle(String)
        case testing(String)
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionTitle("Ollama")
            SettingsCard {
                HStack {
                    Text("Base URL")
                        .frame(width: 64, alignment: .leading)
                    TextField("Base URL", text: $ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
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

                ProviderStatusView(status: ollamaProviderStatus)

                Divider()

                if availableModels.isEmpty {
                    HStack {
                        Text("Model")
                            .frame(width: 64, alignment: .leading)
                        TextField("Model name", text: $ollamaModel)
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
                        Picker("", selection: $ollamaModel) {
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .controlSize(.small)
        .task {
            await fetchModels()
        }
    }

    private var ollamaProviderStatus: ProviderTestStatus {
        switch fetchState {
        case .idle:
            return .idle("Not tested")
        case .loading:
            return .testing("Testing Ollama...")
        case .loaded:
            let count = availableModels.count
            if count == 0 {
                return .success("Connected. No models installed.")
            }
            return .success("Connected. \(count) model(s) installed.")
        case .failed(let message):
            return .failure(message)
        }
    }

    private func fetchModels() async {
        fetchState = .loading
        guard let url = URL(string: "\(ollamaBaseURL)/api/tags") else {
            fetchState = .failed("Invalid URL")
            return
        }
        do {
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "GET"
            let key = ollamaApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                fetchState = .failed("Ollama returned an error response")
                return
            }
            struct TagsResponse: Decodable {
                struct Model: Decodable { let name: String }
                let models: [Model]
            }
            let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
            availableModels = decoded.models.map(\.name)
            // Auto-select first if current selection isn't in the list
            if !availableModels.contains(ollamaModel), let first = availableModels.first {
                ollamaModel = first
            }
            fetchState = .loaded
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .timedOut {
            fetchState = .failed("Cannot connect — is Ollama running? Try: ollama serve")
        } catch {
            fetchState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Profile Tab

struct ProfileSettingsTab: View {
    @AppStorage(WorkflowProfile.storageKey) private var profileText = WorkflowProfile.defaultProfileText

    var body: some View {
        Form {
            Section("Workflow") {
                TextEditor(text: $profileText)
                    .font(.body)
                    .frame(minHeight: 58)
                    .scrollContentBackground(.hidden)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))

                SettingsFooter("Used when scoring app relevance. Re-analyze an app to refresh with this profile.")
            }

            Section {
                Button("Restore Default Profile") {
                    profileText = WorkflowProfile.defaultProfileText
                }
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

    var body: some View {
        Form {
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
