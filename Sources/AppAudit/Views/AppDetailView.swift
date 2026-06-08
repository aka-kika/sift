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
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                Divider()
                recommendationSection
                whatIsThisSection
                Divider()
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
        .sheet(isPresented: $editingDescription) {
            EditDescriptionSheet(appName: app.name, draft: $draftDescription) { saved in
                if saved {
                    let trimmed = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    ensureRecord().userDescription = trimmed.isEmpty ? nil : trimmed
                    saveRecord()
                }
                editingDescription = false
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
                    ensuredRecord.hasLicenseKey = !trimmed.isEmpty
                    saveRecord()
                }
                editingLicenseKey = false
            }
        }
        .sheet(isPresented: $editingURL) {
            EditURLSheet(appName: app.name, draft: $draftURL) { saved in
                if saved {
                    let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ensuredRecord = ensureRecord()
                    let previousURL = ensuredRecord.appURL
                    ensuredRecord.appURL = trimmed.isEmpty ? nil : trimmed
                    if !trimmed.isEmpty {
                        ensuredRecord.suggestedAppURL = nil
                    }
                    saveRecord()
                    if !trimmed.isEmpty, trimmed != previousURL {
                        viewModel.reanalyzeAfterLinkChange(bundleID: app.bundleID, appURL: trimmed)
                    }
                }
                editingURL = false
            }
        }
        .alert("Update with Homebrew?", isPresented: $confirmingHomebrewUpdate) {
            Button("Run Update") { Task { await runHomebrewUpdate() } }
            Button("Copy Command") { copyHomebrewUpdateCommand() }
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
        HStack(alignment: .top, spacing: 16) {
            #if canImport(AppKit)
            if let icon = app.icon {
                Image(nsImage: icon.image)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .cornerRadius(16)
            }
            #endif
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(app.name).font(.title2.weight(.medium))
                    if !app.version.isEmpty {
                        Text(app.version)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    tagBadges
                }
                Text(app.bundleID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                updatePill
            }
            Spacer(minLength: 8)
            overflowMenu
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var tagBadges: some View {
        if app.isFavorite {
            Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
        }
        if app.isMyApp {
            Image(systemName: "hammer.fill").font(.caption).foregroundStyle(.purple)
        }
        if app.isSubscribed {
            Image(systemName: "creditcard.fill").font(.caption).foregroundStyle(.teal)
        }
        if app.isAnalysisLocked {
            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var updatePill: some View {
        switch app.updateState {
        case .checking:
            Label("Checking for updates…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        case .upToDate(let source):
            Label("Up to date · \(source.rawValue)", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .padding(.top, 2)
        case .updateAvailable(let latestVersion, let source, _):
            HStack(spacing: 8) {
                Button {
                    performUpdateAction(source: source)
                } label: {
                    Label(updateActionTitle(latestVersion: latestVersion, source: source),
                          systemImage: updateActionIcon(source: source))
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
                .disabled(runningHomebrewUpdate)
                .help(updateActionHelp(latestVersion: latestVersion, source: source))
                .accessibilityLabel(updateActionAccessibilityLabel(latestVersion: latestVersion, source: source))

                Button("Mark done") {
                    viewModel.acknowledgeUpdate(bundleID: app.bundleID, updateState: app.updateState)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)

                if runningHomebrewUpdate {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.top, 3)
        case .unknown, .unavailable:
            EmptyView()
        }
    }

    private var overflowMenu: some View {
        Menu {
            if case .loaded = app.aiState {
                Button {
                    Task { await viewModel.reanalyze(bundleID: app.bundleID) }
                } label: {
                    Label("Re-analyze", systemImage: "arrow.clockwise")
                }
                .disabled(app.isAnalysisLocked)
            }
            Button {
                toggleAnalysisLock()
            } label: {
                Label(app.isAnalysisLocked ? "Unlock Analysis" : "Lock Analysis",
                      systemImage: app.isAnalysisLocked ? "lock.open" : "lock.fill")
            }
            Button {
                draftDescription = record?.userDescription ?? ""
                editingDescription = true
            } label: {
                Label(userDescription != nil ? "Edit Description" : "Customize Description",
                      systemImage: "pencil")
            }
            if userDescription != nil {
                Button(role: .destructive) {
                    record?.userDescription = nil
                    saveRecord()
                } label: {
                    Label("Remove Custom Description", systemImage: "person.fill.xmark")
                }
            }

            Divider()

            Button {
                toggleFavorite()
            } label: {
                Label(app.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: app.isFavorite ? "star.slash" : "star")
            }
            Button {
                toggleMyApp()
            } label: {
                Label(app.isMyApp ? "Unmark as My App" : "Mark as My App",
                      systemImage: app.isMyApp ? "hammer.slash" : "hammer.fill")
            }
            Button {
                toggleSubscription()
            } label: {
                Label(app.isSubscribed ? "Unmark Subscription" : "Mark as Subscription",
                      systemImage: "creditcard")
            }

            Divider()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
            } label: {
                Label("Open App", systemImage: "arrow.up.right.square")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.bundleID, forType: .string)
            } label: {
                Label("Copy Bundle ID", systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
    }

    // MARK: - Recommendation (ranking first)

    @ViewBuilder
    private var recommendationSection: some View {
        switch app.aiState {
        case .loaded(_, let score, let reason, let bestUse):
            VStack(alignment: .leading, spacing: 8) {
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

                if !bestUse.isEmpty {
                    Text(bestUse)
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(reason)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .pending:
            ProgressView("Waiting to analyze…")
                .frame(maxWidth: .infinity, alignment: .center)

        case .loading:
            VStack(spacing: 8) {
                ProgressView("Analyzing with \(AnalysisProviderKind.current().displayName)…")
                Text("Using local AI. This may take a moment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)

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

    // MARK: - What is this?

    @ViewBuilder
    private var whatIsThisSection: some View {
        let explanation: String? = {
            if case .loaded(let value, _, _, _) = app.aiState { return value }
            return nil
        }()

        if explanation != nil || userDescription != nil {
            VStack(alignment: .leading, spacing: 8) {
                Label("What is this?", systemImage: "info.circle.fill")
                    .font(.subheadline.weight(.semibold))

                if let userDescription {
                    userDescriptionCard(userDescription)
                }

                if let explanation {
                    VStack(alignment: .leading, spacing: 4) {
                        if userDescription != nil {
                            Text("AI explanation")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(explanation)
                            .font(.body)
                            .foregroundStyle(userDescription != nil ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func userDescriptionCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "person.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Your description")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Utility rows

    private var utilitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            notesSection
            DetailRowDivider()
            licenseKeySection
            DetailRowDivider()
            urlSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notesSection: some View {
        DisclosureGroup(isExpanded: $notesExpanded) {
            NotesEditor(
                text: Binding(
                    get: { record?.notes ?? "" },
                    set: { ensureRecord().notes = $0.isEmpty ? nil : $0; saveRecord() }
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

    private var licenseKeySection: some View {
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
                    record?.hasLicenseKey = false
                    saveRecord()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove license key")
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var urlSection: some View {
        HStack(spacing: 8) {
            Label("App Link", systemImage: "link")
                .font(.subheadline.weight(.semibold))
            if let urlString = record?.appURL, !urlString.isEmpty,
               let url = URL(string: urlString) {
                Link(urlString, destination: url)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let suggestedURLString = record?.suggestedAppURL, !suggestedURLString.isEmpty,
                      let suggestedURL = URL(string: suggestedURLString) {
                Link("Suggested: \(suggestedURLString)", destination: suggestedURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if record?.appURL == nil,
               let suggestedURL = record?.suggestedAppURL,
               !suggestedURL.isEmpty {
                Button {
                    approveSuggestedAppURL(suggestedURL)
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.green)
                .help("Use suggested app link")
            }
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
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove app link")
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func approveSuggestedAppURL(_ suggestedURL: String) {
        let ensuredRecord = ensureRecord()
        let trimmed = suggestedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let previousURL = ensuredRecord.appURL
        ensuredRecord.appURL = trimmed
        ensuredRecord.suggestedAppURL = nil
        saveRecord()

        if trimmed != previousURL {
            viewModel.reanalyzeAfterLinkChange(bundleID: app.bundleID, appURL: trimmed)
        }
    }

    // MARK: - Record helpers

    private var userDescription: String? {
        guard let value = record?.userDescription, !value.isEmpty else { return nil }
        return value
    }

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

    private func toggleFavorite() {
        let ensuredRecord = ensureRecord()
        ensuredRecord.isFavorite.toggle()
        viewModel.setFavorite(bundleID: app.bundleID, value: ensuredRecord.isFavorite)
        saveRecord()
    }

    private func toggleMyApp() {
        let ensuredRecord = ensureRecord()
        ensuredRecord.isMyApp.toggle()
        viewModel.setMyApp(bundleID: app.bundleID, value: ensuredRecord.isMyApp)
        saveRecord()
    }

    private func toggleSubscription() {
        let ensuredRecord = ensureRecord()
        ensuredRecord.hasSubscription.toggle()
        viewModel.setSubscription(bundleID: app.bundleID, value: ensuredRecord.hasSubscription)
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

    // MARK: - Score helpers

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

    // MARK: - Update helpers

    private func updateActionTitle(latestVersion: String, source: AppInfo.UpdateSource) -> String {
        switch source {
        case .appStore: return "Update to \(latestVersion)"
        case .sparkle: return "Update to \(latestVersion)"
        case .homebrew: return "Update to \(latestVersion)"
        }
    }

    private func updateActionHelp(latestVersion: String, source: AppInfo.UpdateSource) -> String {
        switch source {
        case .appStore: return "Open \(app.name) in the App Store to update to \(latestVersion)."
        case .sparkle: return "Open \(app.name)'s download page for \(latestVersion)."
        case .homebrew: return "Run or copy \(app.homebrewUpdateCommand ?? "brew upgrade --cask ...")"
        }
    }

    private func updateActionAccessibilityLabel(latestVersion: String, source: AppInfo.UpdateSource) -> String {
        switch source {
        case .appStore: return "Open \(app.name) in App Store, version \(latestVersion)"
        case .sparkle: return "Open \(app.name) download, version \(latestVersion)"
        case .homebrew: return "Open Homebrew update options for \(app.name), version \(latestVersion)"
        }
    }

    private func updateActionIcon(source: AppInfo.UpdateSource) -> String {
        switch source {
        case .appStore: return "bag.fill"
        case .sparkle: return "sparkles"
        case .homebrew: return "terminal.fill"
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
