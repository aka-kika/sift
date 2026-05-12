import SwiftUI
import SwiftData

#if canImport(AppKit)
import AppKit
#endif

struct AppDetailView: View {
    let app: AppInfo
    @Environment(AppListViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    private let licenseKeyStore = LicenseKeyStore.shared

    @State private var record: AppRecord? = nil
    @State private var editingDescription = false
    @State private var draftDescription = ""
    @State private var editingURL = false
    @State private var draftURL = ""
    @State private var editingLicenseKey = false
    @State private var draftLicenseKey = ""
    @State private var currentLicenseKey: String? = nil
    @State private var notesExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                Divider()
                aiSection
                Divider()
                notesSection
                Divider()
                licenseKeySection
                Divider()
                urlSection
            }
            .padding(24)
        }
        .navigationTitle(app.name)
        .task(id: app.bundleID) {
            loadRecord()
            loadLicenseKey()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            #if canImport(AppKit)
            if let icon = app.icon {
                Image(nsImage: icon.image)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .cornerRadius(16)
            }
            #endif
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.title.bold())
                Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                if !app.version.isEmpty {
                    Text("Version \(app.version)").font(.caption).foregroundStyle(.secondary)
                }
                updateStatusView
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch app.updateState {
        case .checking:
            Label("Checking for updates...", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .upToDate(let source):
            Label("Up to date via \(source.rawValue)", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .updateAvailable(let latestVersion, let source, _):
            VStack(alignment: .leading, spacing: 6) {
                if let updateURL = app.updateState.actionURL {
                    Button {
                        NSWorkspace.shared.open(updateURL)
                    } label: {
                        Label("Update available: \(latestVersion) via \(source.rawValue)", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("Update available: \(latestVersion) via \(source.rawValue)", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    viewModel.acknowledgeUpdate(bundleID: app.bundleID, updateState: app.updateState)
                } label: {
                    Label("Mark Updated", systemImage: "checkmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        case .unknown, .unavailable:
            EmptyView()
        }
    }

    // MARK: - AI / Description section

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // What is this?
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("What is this?", systemImage: "info.circle.fill").font(.headline)
                    Spacer()
                    Button {
                        draftDescription = record?.userDescription ?? ""
                        editingDescription = true
                    } label: {
                        Label(record?.userDescription != nil ? "Edit" : "Customize",
                              systemImage: record?.userDescription != nil ? "pencil" : "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }

                // User description (if any) shown first
                if let userDesc = record?.userDescription, !userDesc.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Your description")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(userDesc)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                }

                // AI explanation
                switch app.aiState {
                case .pending:
                    ProgressView("Waiting to analyze…").frame(maxWidth: .infinity)

                case .loading:
                    VStack(spacing: 8) {
                        ProgressView("Analyzing with \(AnalysisProviderKind.current().displayName)...")
                        Text("Using local AI. This may take a moment.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)

                case .loaded(let explanation, _, _, _):
                    VStack(alignment: .leading, spacing: 4) {
                        if record?.userDescription != nil {
                            Text("AI explanation")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(explanation)
                            .font(.body)
                            .foregroundStyle(record?.userDescription != nil ? .secondary : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                case .unavailable(let msg):
                    ContentUnavailableView {
                        Label("AI Unavailable", systemImage: "brain.slash")
                    } description: {
                        Text(msg)
                    } actions: {
                        Button("Retry") {
                            Task { await viewModel.reanalyze(bundleID: app.bundleID) }
                        }
                    }
                }
            }

            // Best Use
            if case .loaded(_, _, _, let bestUse) = app.aiState, !bestUse.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Best use for you", systemImage: "bolt.fill").font(.headline)
                    Text(bestUse)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Relevance score
            if case .loaded(_, let score, let reason, _) = app.aiState {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Do you need this?", systemImage: "checkmark.seal.fill").font(.headline)
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { i in
                            Circle()
                                .fill(i <= score ? colorForScore(score) : Color.secondary.opacity(0.2))
                                .frame(width: 16, height: 16)
                        }
                        Text(scoreLabel(score))
                            .font(.subheadline.bold())
                            .foregroundStyle(colorForScore(score))
                    }
                    Text(reason).font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Actions
            HStack(spacing: 8) {
                if case .loaded(_, _, _, _) = app.aiState {
                    Button {
                        Task { await viewModel.reanalyze(bundleID: app.bundleID) }
                    } label: {
                        Label("Re-analyze", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                if let _ = record?.userDescription {
                    Button(role: .destructive) {
                        record?.userDescription = nil
                        saveRecord()
                    } label: {
                        Label("Remove custom description", systemImage: "person.fill.xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $editingDescription) {
            EditDescriptionSheet(
                appName: app.name,
                draft: $draftDescription
            ) { saved in
                if saved {
                    let trimmed = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    record?.userDescription = trimmed.isEmpty ? nil : trimmed
                    saveRecord()
                }
                editingDescription = false
            }
        }
    }

    // MARK: - Notes section

    private var notesSection: some View {
        DisclosureGroup(isExpanded: $notesExpanded) {
            NotesEditor(
                text: Binding(
                    get: { record?.notes ?? "" },
                    set: { record?.notes = $0.isEmpty ? nil : $0; saveRecord() }
                )
            )
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Label("Notes", systemImage: "note.text").font(.headline)
                if let notes = record?.notes, !notes.isEmpty {
                    Text("Saved")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: app.bundleID) { _, _ in
            notesExpanded = false
        }
    }

    // MARK: - License Key section

    private var licenseKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("License Key", systemImage: "key.horizontal").font(.headline)
                Spacer()
                Button {
                    draftLicenseKey = currentLicenseKey ?? ""
                    editingLicenseKey = true
                } label: {
                    Label(currentLicenseKey != nil ? "Edit" : "Add Key",
                          systemImage: currentLicenseKey != nil ? "pencil" : "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            if let licenseKey = currentLicenseKey, !licenseKey.isEmpty {
                HStack(spacing: 8) {
                    Text(maskedLicenseKey(licenseKey))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(licenseKey, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        licenseKeyStore.delete(bundleID: app.bundleID)
                        currentLicenseKey = nil
                        record?.licenseKey = nil
                        saveRecord()
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Store a purchased license key for this app so you can copy it later.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .sheet(isPresented: $editingLicenseKey) {
            DetailLicenseKeySheet(appName: app.name, draft: $draftLicenseKey) { saved in
                if saved {
                    let trimmed = draftLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ensuredRecord = ensureRecord()
                    licenseKeyStore.save(trimmed, bundleID: app.bundleID)
                    currentLicenseKey = trimmed.isEmpty ? nil : trimmed
                    ensuredRecord.licenseKey = nil
                    saveRecord()
                }
                editingLicenseKey = false
            }
        }
    }

    // MARK: - URL section

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("App Link", systemImage: "link").font(.headline)
                Spacer()
                Button {
                    draftURL = record?.appURL ?? ""
                    editingURL = true
                } label: {
                    Label(record?.appURL != nil ? "Edit" : "Add Link",
                          systemImage: record?.appURL != nil ? "pencil" : "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            if let urlString = record?.appURL, !urlString.isEmpty,
               let url = URL(string: urlString) {
                HStack(spacing: 4) {
                    Link(urlString, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(role: .destructive) {
                        record?.appURL = nil
                        saveRecord()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Text("Add a GitHub repo or website so the selected analysis provider can use it as context.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .sheet(isPresented: $editingURL) {
            EditURLSheet(appName: app.name, draft: $draftURL) { saved in
                if saved {
                    let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    record?.appURL = trimmed.isEmpty ? nil : trimmed
                    saveRecord()
                }
                editingURL = false
            }
        }
    }

    // MARK: - Helpers

    private func loadRecord() {
        let id = app.bundleID
        let descriptor = FetchDescriptor<AppRecord>(predicate: #Predicate { $0.bundleID == id })
        record = try? modelContext.fetch(descriptor).first
    }

    private func loadLicenseKey() {
        let resolution = licenseKeyStore.resolveKey(bundleID: app.bundleID, legacyValue: record?.licenseKey)
        currentLicenseKey = resolution.value
        if resolution.didMigrateLegacyValue, let record {
            record.licenseKey = nil
            saveRecord()
        }
    }

    private func saveRecord() {
        try? modelContext.save()
    }

    private func ensureRecord() -> AppRecord {
        if let record {
            return record
        }

        let created = AppRecord(
            bundleID: app.bundleID,
            appName: app.name,
            explanation: "",
            relevanceScore: 0,
            relevanceReason: "",
            bestUse: "",
            ollamaModel: ""
        )
        modelContext.insert(created)
        record = created
        return created
    }

    private func maskedLicenseKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed }
        return "\(trimmed.prefix(4))••••\(trimmed.suffix(4))"
    }

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 1: return "Not needed"
        case 2: return "Unlikely needed"
        case 3: return "Possibly useful"
        case 4: return "Likely useful"
        case 5: return "Essential"
        default: return "Unknown"
        }
    }

    private func colorForScore(_ score: Int) -> Color {
        switch score {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .mint
        case 5: return .green
        default: return .gray
        }
    }
}

struct DetailLicenseKeySheet: View {
    let appName: String
    @Binding var draft: String
    let onDone: (Bool) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("License key for \(appName)")
                .font(.headline)
            Text("Store the purchased key for this app so you can copy it later.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("Enter license key", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)

            HStack {
                Button("Cancel") { onDone(false) }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Clear") { draft = ""; onDone(true) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button("Save") { onDone(true) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { focused = true }
    }
}

// MARK: - Edit Description Sheet

struct EditDescriptionSheet: View {
    let appName: String
    @Binding var draft: String
    let onDone: (Bool) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your description for \(appName)")
                .font(.headline)
            Text("Override the AI explanation with your own. This is shown first and preserved across re-analyses.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                .focused($focused)

            HStack {
                Button("Cancel") { onDone(false) }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Clear") { draft = ""; onDone(true) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button("Save") { onDone(true) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { focused = true }
    }
}

// MARK: - Edit URL Sheet

struct EditURLSheet: View {
    let appName: String
    @Binding var draft: String
    let onDone: (Bool) -> Void

    @FocusState private var focused: Bool

    private var isValidURL: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || URL(string: trimmed) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App link for \(appName)")
                .font(.headline)
            Text("GitHub repo or website. The selected analysis provider will use this as context when the app is analyzed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("https://github.com/author/repo", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)

            if !isValidURL {
                Text("Not a valid URL")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { onDone(false) }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Clear") { draft = ""; onDone(true) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button("Save") { onDone(true) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidURL)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { focused = true }
    }
}

// MARK: - Notes Editor

struct NotesEditor: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty && !focused {
                Text("Add notes about this app — when you last used it, why you installed it, whether to keep or delete…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(8)
        }
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
    }
}
