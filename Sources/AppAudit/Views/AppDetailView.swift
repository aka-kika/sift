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
    @State private var confirmingHomebrewUpdate = false
    @State private var runningHomebrewUpdate = false
    @State private var homebrewUpdateMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerSection
                Divider()
                aiSection
                utilitySection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .navigationTitle(app.name)
        .task(id: app.bundleID) {
            loadRecord()
            loadLicenseKey()
        }
        .alert("Update with Homebrew?", isPresented: $confirmingHomebrewUpdate) {
            Button("Run Update") {
                Task { await runHomebrewUpdate() }
            }
            Button("Copy Command") {
                copyHomebrewUpdateCommand()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(app.homebrewUpdateCommand ?? "brew upgrade --cask <token>")
        }
        .alert(
            "Homebrew Update",
            isPresented: Binding(
                get: { homebrewUpdateMessage != nil },
                set: { if !$0 { homebrewUpdateMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(homebrewUpdateMessage ?? "")
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
                Text(app.name).font(.title2.weight(.medium))
                Text(app.bundleID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if !app.version.isEmpty {
                    Text("Version \(app.version)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                updateStatusView
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch app.updateState {
        case .checking:
            Label("Checking for updates...", systemImage: "arrow.triangle.2.circlepath")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .upToDate(let source):
            Label("Up to date via \(source.rawValue)", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .updateAvailable(let latestVersion, let source, _):
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    performUpdateAction(source: source)
                } label: {
                    Label(updateActionTitle(latestVersion: latestVersion, source: source), systemImage: updateActionIcon(source: source))
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .disabled(runningHomebrewUpdate)
                .help(updateActionHelp(latestVersion: latestVersion, source: source))
                .accessibilityLabel(updateActionAccessibilityLabel(latestVersion: latestVersion, source: source))

                if runningHomebrewUpdate {
                    ProgressView("Running Homebrew update...")
                        .font(.callout)
                        .controlSize(.small)
                }

                Button {
                    viewModel.acknowledgeUpdate(bundleID: app.bundleID, updateState: app.updateState)
                } label: {
                    Label("Mark Updated", systemImage: "checkmark.circle")
                        .font(.callout)
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
                    Label("What is this?", systemImage: "info.circle.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        toggleAnalysisLock()
                    } label: {
                        Label(app.isAnalysisLocked ? "Unlock" : "Lock",
                              systemImage: app.isAnalysisLocked ? "lock.fill" : "lock.open")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(app.isAnalysisLocked ? .orange : .secondary)
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

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

            // Best use and relevance
            if case .loaded(_, let score, let reason, let bestUse) = app.aiState {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Best use and ranking for your needs", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))

                    if !bestUse.isEmpty {
                        Text(bestUse)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { i in
                            Circle()
                                .fill(i <= score ? colorForScore(score) : Color.secondary.opacity(0.2))
                                .frame(width: 16, height: 16)
                        }
                        Text(scoreLabel(score))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colorForScore(score))
                    }

                    Text(reason)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Actions
            HStack(spacing: 8) {
                if case .loaded(_, _, _, _) = app.aiState {
                    Button {
                        Task { await viewModel.reanalyze(bundleID: app.bundleID) }
                    } label: {
                        Label(app.isAnalysisLocked ? "Locked" : "Re-analyze",
                              systemImage: app.isAnalysisLocked ? "lock.fill" : "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(app.isAnalysisLocked)
                    if app.isAnalysisLocked {
                        Text("Locked analysis will not be regenerated automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Utility section

    private var utilitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            notesSection
            DetailRowDivider()
            licenseKeySection
            DetailRowDivider()
            urlSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Label("Notes", systemImage: "note.text")
                    .font(.subheadline.weight(.semibold))
                if let notes = record?.notes, !notes.isEmpty {
                    Text("Saved")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .onChange(of: app.bundleID) { _, _ in
            notesExpanded = false
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - License Key section

    private var licenseKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("License Key", systemImage: "key.horizontal")
                    .font(.subheadline.weight(.semibold))
                if let licenseKey = currentLicenseKey, !licenseKey.isEmpty {
                    Text(maskedLicenseKey(licenseKey))
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .textSelection(.enabled)
                } else {
                    Text("None")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let licenseKey = currentLicenseKey, !licenseKey.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(licenseKey, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Copy license key")
                }
                Button {
                    draftLicenseKey = currentLicenseKey ?? ""
                    editingLicenseKey = true
                } label: {
                    Image(systemName: currentLicenseKey != nil ? "pencil" : "plus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(currentLicenseKey != nil ? "Edit license key" : "Add license key")

                if currentLicenseKey != nil {
                    Button(role: .destructive) {
                        licenseKeyStore.delete(bundleID: app.bundleID)
                        currentLicenseKey = nil
                        record?.licenseKey = nil
                        saveRecord()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove license key")
                }
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            HStack(spacing: 8) {
                Label("App Link", systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                if let urlString = record?.appURL, !urlString.isEmpty,
                   let url = URL(string: urlString) {
                    Link(urlString, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("None")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    draftURL = record?.appURL ?? ""
                    editingURL = true
                } label: {
                    Image(systemName: record?.appURL != nil ? "pencil" : "plus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(record?.appURL != nil ? "Edit app link" : "Add app link")
                if record?.appURL != nil {
                    Button(role: .destructive) {
                        record?.appURL = nil
                        saveRecord()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove app link")
                }
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $editingURL) {
            EditURLSheet(appName: app.name, draft: $draftURL) { saved in
                if saved {
                    let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ensuredRecord = ensureRecord()
                    let previousURL = ensuredRecord.appURL
                    ensuredRecord.appURL = trimmed.isEmpty ? nil : trimmed
                    saveRecord()
                    if !trimmed.isEmpty, trimmed != previousURL {
                        viewModel.reanalyzeAfterLinkChange(bundleID: app.bundleID, appURL: trimmed)
                    }
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

    private func toggleAnalysisLock() {
        let ensuredRecord = ensureRecord()
        ensuredRecord.isAnalysisLocked.toggle()
        viewModel.setAnalysisLocked(bundleID: app.bundleID, value: ensuredRecord.isAnalysisLocked)
        saveRecord()
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

    private func updateActionTitle(latestVersion: String, source: AppInfo.UpdateSource) -> String {
        switch source {
        case .appStore:
            return "Open in App Store: \(latestVersion)"
        case .sparkle:
            return "Open Download: \(latestVersion)"
        case .homebrew:
            return "Update with Homebrew: \(latestVersion)"
        }
    }

    private func updateActionHelp(latestVersion: String, source: AppInfo.UpdateSource) -> String {
        switch source {
        case .appStore:
            return "Open \(app.name) in the App Store to update to \(latestVersion)."
        case .sparkle:
            return "Open \(app.name)'s download page for \(latestVersion)."
        case .homebrew:
            return "Run or copy \(app.homebrewUpdateCommand ?? "brew upgrade --cask ...")"
        }
    }

    private func updateActionAccessibilityLabel(latestVersion: String, source: AppInfo.UpdateSource) -> String {
        switch source {
        case .appStore:
            return "Open \(app.name) in App Store, version \(latestVersion)"
        case .sparkle:
            return "Open \(app.name) download, version \(latestVersion)"
        case .homebrew:
            return "Open Homebrew update options for \(app.name), version \(latestVersion)"
        }
    }

    private func updateActionIcon(source: AppInfo.UpdateSource) -> String {
        switch source {
        case .appStore:
            return "bag.fill"
        case .sparkle:
            return "sparkles"
        case .homebrew:
            return "terminal.fill"
        }
    }

    private func performUpdateAction(source: AppInfo.UpdateSource) {
        switch source {
        case .appStore, .sparkle:
            if let updateURL = app.updateState.actionURL {
                NSWorkspace.shared.open(updateURL)
            }
        case .homebrew:
            confirmingHomebrewUpdate = true
        }
    }

    private func copyHomebrewUpdateCommand() {
        guard let command = app.homebrewUpdateCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    private func runHomebrewUpdate() async {
        guard let token = app.homebrewCaskToken else { return }
        runningHomebrewUpdate = true
        let output = await Task.detached {
            HomebrewService().upgradeCask(token)
        }.value
        runningHomebrewUpdate = false
        homebrewUpdateMessage = output.isEmpty ? "Homebrew finished. Rescan to refresh this app's version." : output
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
            Text("GitHub repo or website. Saving a new link re-analyzes the app unless its analysis is locked.")
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 76)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DetailRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 28)
    }
}
