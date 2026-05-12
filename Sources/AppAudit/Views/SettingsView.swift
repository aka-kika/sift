import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            OllamaSettingsTab()
                .tabItem { Label("Ollama", systemImage: "brain") }

            ProfileSettingsTab()
                .tabItem { Label("Profile", systemImage: "person.text.rectangle") }

            ScanningSettingsTab()
                .tabItem { Label("Scanning", systemImage: "folder.badge.gearshape") }
        }
        .frame(width: 500, height: 340)
    }
}

// MARK: - Ollama Tab

struct OllamaSettingsTab: View {
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = "http://localhost:11434"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"

    @State private var availableModels: [String] = []
    @State private var fetchState: FetchState = .idle

    enum FetchState { case idle, loading, loaded, failed(String) }

    var body: some View {
        Form {
            Section("Connection") {
                HStack {
                    TextField("Base URL", text: $ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
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
            }

            Section("Model") {
                if availableModels.isEmpty {
                    HStack {
                        TextField("Model name", text: $ollamaModel)
                            .textFieldStyle(.roundedBorder)
                        Button("Fetch Models") {
                            Task { await fetchModels() }
                        }
                        .buttonStyle(.bordered)
                    }
                    if case .failed(let msg) = fetchState {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Click Fetch Models or the refresh button to load installed models")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Active Model", selection: $ollamaModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("\(availableModels.count) model(s) installed locally")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await fetchModels() }
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
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))

                Text("Used by Ollama when scoring app relevance. Re-analyze an app to refresh its result with the current profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore Default Profile") {
                    profileText = WorkflowProfile.defaultProfileText
                }
            }
        }
        .formStyle(.grouped)
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
                Text("Changes take effect on the next rescan (⌘R).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
