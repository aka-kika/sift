import SwiftUI
import SwiftData

#if canImport(AppKit)
import AppKit
#endif

struct AppDetailView: View {
    let app: AppInfo
    @AppStorage("developerMode") private var developerMode = false
    @Environment(AppListViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    private let licenseKeyStore = LicenseKeyStore.shared

    @State private var record: AppRecord? = nil
    @State private var editingDescription = false
    @State private var draftDescription = ""
    @State private var editingURL = false
    @State private var draftURL = ""
    @State private var moneyPopoverPresented = false
    @State private var moneyPopoverStartsOnSubscription = false
    @State private var draftLicenseKey = ""
    @State private var draftLicenseEmail = ""
    @State private var draftLicenseType: LicenseType? = nil
    @State private var currentLicenseKey: String? = nil
    @State private var notesSheetPresented = false
    @State private var notesSessionBundleID: String? = nil
    @State private var notesSessionInitialNotes: String? = nil
    @State private var similarResults: [SimilarApp]? = nil
    @State private var findingSimilar = false
    @State private var draftSubPrice = ""
    @State private var draftSubCurrency = ""
    @State private var draftSubCycle: BillingCycle = .monthly
    @State private var draftSubRenewal = Date()
    @State private var draftSubEmail = ""
    @State private var confirmingHomebrewUpdate = false
    @State private var runningHomebrewUpdate = false
    @State private var homebrewUpdateMessage: String? = nil
    @State private var docsMessage: String? = nil
    @State private var hoveredCubeInfo: String? = nil
    @State private var bundleSizeBytes: Int64? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    whatIsThisSection
                    recommendationSection
                    improveAnalysisCallout
                    if case .loaded = app.aiState {
                        similarSection
                    }
                }
                factsSection
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .softTopScrollEdge()
        .navigationTitle(app.name)
        .task(id: app.bundleID) {
            loadRecord()
            loadLicenseKey()
            similarResults = nil
            findingSimilar = false
            consumeLicensePopoverRequest()
        }
        .onChange(of: viewModel.licensePopoverRequestID) { _, _ in
            consumeLicensePopoverRequest()
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
        .sheet(isPresented: $notesSheetPresented) {
            NotesSheet(
                appName: app.name,
                text: Binding(
                    get: { record?.notes ?? "" },
                    set: { ensureRecord().notes = $0.isEmpty ? nil : $0; saveRecord() }
                )
            ) {
                notesSheetPresented = false
            }
        }
        .onChange(of: notesSheetPresented) { _, presented in
            if presented {
                notesSessionBundleID = app.bundleID
                notesSessionInitialNotes = record?.notes
            } else {
                endNotesSession()
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
        .alert(
            "Docs",
            isPresented: Binding(
                get: { docsMessage != nil },
                set: { if !$0 { docsMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(docsMessage ?? "")
        }
    }

    // MARK: - Shared type

    /// The one micro-label style on this page: small, uppercase, tertiary.
    /// Used above every fact cell and above each block of analysis prose, so
    /// a caption always reads as a caption and never competes with the text
    /// it introduces.
    private func microLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
    }

    /// Section headings across the detail page: one size, one weight, with a
    /// quiet glyph that names the section rather than decorating it.
    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.title3.weight(.semibold))
        }
    }

    // MARK: - Facts

    /// Closes the page with what the prose above never says: room taken, last
    /// opened, where it came from, what it costs. Everything is already on
    /// hand except the bundle size, which is measured off the main thread.
    /// Labels stay tertiary and there are no boxes — the row should read as a
    /// footnote, not a second dashboard.
    private var factsSection: some View {
        let facts = AppFacts.build(
            sizeBytes: bundleSizeBytes,
            lastUsed: app.lastUsedDate,
            now: Date(),
            installSource: app.installSourceLabel,
            analyzedAt: record?.generatedAt
        )
        return VStack(alignment: .leading, spacing: 12) {
            Divider()
            // Four cells share the width evenly and never wrap — the row is a
            // single line by construction, not by luck.
            HStack(alignment: .top, spacing: 16) {
                ForEach(facts) { fact in
                    VStack(alignment: .leading, spacing: 2) {
                        microLabel(fact.label)
                        Text(fact.value)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: app.bundleID) {
            bundleSizeBytes = nil
            let path = app.path
            bundleSizeBytes = await Task.detached {
                LeftoverScanner.size(of: URL(fileURLWithPath: path))
            }.value
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(app.name).font(.title2.weight(.medium)).lineLimit(1)
                    if !app.version.isEmpty {
                        Text(app.version)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    tagBadges
                }
                if let categoryName = AppCategory.humanName(for: app.category) {
                    Text(categoryName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(app.bundleID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                updatePill
            }
            .layoutPriority(1)
            headerUtilities
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Feeds the label strip: hovering shows the text instantly, leaving
    /// clears it only if another cube hasn't already claimed the strip.
    private func stripInfo<V: View>(_ view: V, _ text: String) -> some View {
        let line = text.components(separatedBy: "\n").first ?? text
        return view.onHover { hovering in
            if hovering {
                hoveredCubeInfo = line
            } else if hoveredCubeInfo == line {
                hoveredCubeInfo = nil
            }
        }
    }

    /// The utility cube strip lives in the header's empty right side. A
    /// matching re-analyze chip leads it (the old ⋯ menu is gone; Lock is the
    /// lock cube, and Customize Description moved into "What is this?").
    ///
    /// The grid balances itself: one line up to 5 cubes, otherwise two even
    /// rows (6 → 3+3, 7 → 4+3, 8 → 4+4, 9 → 5+4), so no ragged tail like the
    /// old fixed 5-column layout produced.
    private var cubeCount: Int {
        var count = 5
        if case .loaded = app.aiState { count += 1 }
        if developerMode { count += 2 }
        return count
    }

    private var gridColumns: Int {
        cubeCount <= 5 ? cubeCount : (cubeCount + 1) / 2
    }

    private var gridWidth: CGFloat {
        CGFloat(gridColumns) * 34 + CGFloat(gridColumns - 1) * 8
    }

    private var headerUtilities: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: gridColumns),
                spacing: 8
            ) {
                if case .loaded = app.aiState {
                    stripInfo(reanalyzeChip, "Re-analyze the AI description")
                }
                stripInfo(notesCard, notesHelp)
                stripInfo(moneyCard, moneyStripLabel)
                stripInfo(linkCard, linkHelp)
                stripInfo(lockCard, app.isAnalysisLocked
                          ? "Lock — analysis frozen, click to unlock"
                          : "Lock — freeze the analysis")
                stripInfo(favoriteCard, app.isFavorite ? "Favorite — click to unmark" : "Mark as favorite")
                if developerMode {
                    stripInfo(myAppCard, app.isMyApp
                              ? "My App — you build this, click to unmark"
                              : "Mark as My App (a project you build)")
                    stripInfo(docsCard, docsHelp)
                }
            }
            Text(hoveredCubeInfo ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: gridWidth, alignment: .leading)
        }
        .frame(width: gridWidth)
    }

    private var reanalyzeChip: some View {
        Button {
            Task { await viewModel.reanalyze(bundleID: app.bundleID) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(app.isAnalysisLocked)
        .help("Re-analyze")
    }

    /// Marks this app as one you build. It also gates the Docs cube — only a
    /// My App can attach a local project folder as evidence.
    private var myAppCard: some View {
        UtilityCard(tint: .purple, active: app.isMyApp, action: { toggleMyApp() }) {
            cardIcon(app.isMyApp ? "hammer.fill" : "hammer", tint: app.isMyApp ? .purple : .secondary)
        }
        .help(app.isMyApp ? "Your app — click to unmark" : "Mark as My App (a project you build)")
    }

    private func toggleMyApp() {
        let ensured = ensureRecord()
        ensured.isMyApp.toggle()
        viewModel.setMyApp(bundleID: app.bundleID, value: ensured.isMyApp)
        saveRecord()
    }

    @ViewBuilder
    private var tagBadges: some View {
        if app.isFavorite {
            Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
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
                .glassProminentButtonStyle()
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

    // MARK: - Recommendation (ranking first)

    @ViewBuilder
    private var recommendationSection: some View {
        switch app.aiState {
        case .loaded(_, let score, let reason, let bestUse):
            VStack(alignment: .leading, spacing: 16) {
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

                // Two different claims wearing the same grey: what the app is
                // good for, and why it scored what it scored. Naming each one
                // stops the second from reading as a stray afterthought.
                if !bestUse.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        microLabel("Good for")
                        Text(bestUse)
                            .font(.body)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    microLabel("Tip")
                    Text(reason)
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    // MARK: - Improve-analysis callout

    @ViewBuilder
    private var improveAnalysisCallout: some View {
        if case .loaded(_, let score, _, _) = app.aiState,
           AppInfo.needsLinkHelp(score: score,
                                 hasAppURL: !((record?.appURL ?? "").isEmpty),
                                 isLocked: app.isAnalysisLocked) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sift couldn't confidently identify this app.")
                        .font(.callout)
                    Text("Adding its website or GitHub link gives the analysis real evidence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Add Link") {
                    draftURL = record?.appURL ?? record?.suggestedAppURL ?? ""
                    editingURL = true
                }
                .glassButtonStyle()
                .controlSize(.small)
            }
            .padding(12)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    sectionTitle("What is this?", systemImage: "text.alignleft")
                    Spacer()
                    Button {
                        draftDescription = record?.userDescription ?? ""
                        editingDescription = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(userDescription != nil ? "Edit your description (clear it to remove)" : "Customize the description")
                }

                if let userDescription {
                    userDescriptionCard(userDescription)
                }

                if let explanation {
                    VStack(alignment: .leading, spacing: 4) {
                        if userDescription != nil {
                            microLabel("AI explanation")
                        }
                        Text(explanation)
                            .font(.body)
                            .lineSpacing(3)
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
                    .foregroundStyle(.tertiary)
                microLabel("Your description")
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

    // MARK: - Utility cards

    // MARK: - Similar apps

    @ViewBuilder
    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if findingSimilar {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Finding similar apps you have…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let results = similarResults {
                if results.isEmpty {
                    HStack(spacing: 8) {
                        Text("No clear overlap among your installed apps.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Try again") { runFindSimilar() }
                            .buttonStyle(.borderless)
                            .font(.callout)
                    }
                } else {
                    HStack {
                        Label("Similar apps you have", systemImage: "square.on.square")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button { runFindSimilar() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Find again")
                    }
                    VStack(spacing: 6) {
                        ForEach(results) { similarRow($0) }
                    }
                }
            }
            // Idle: nothing here — the Cross-App cube up top is the trigger.
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func similarRow(_ similar: SimilarApp) -> some View {
        let info = viewModel.apps.first(where: { $0.bundleID == similar.bundleID })
        return Button {
            viewModel.selectedAppID = similar.bundleID
        } label: {
            HStack(spacing: 10) {
                if let icon = info?.icon {
                    Image(nsImage: icon.image)
                        .resizable()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 26, height: 26)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(similar.name).font(.callout.weight(.medium))
                    if !similar.reason.isEmpty {
                        Text(similar.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func runFindSimilar() {
        findingSimilar = true
        similarResults = nil
        let bundleID = app.bundleID
        Task {
            let results = await viewModel.findSimilarApps(to: bundleID)
            // Ignore a stale result if the user switched apps mid-request.
            guard app.bundleID == bundleID else { return }
            similarResults = results
            findingSimilar = false
        }
    }

    private var lockCard: some View {
        let locked = app.isAnalysisLocked
        return UtilityCard(tint: .orange, active: locked, action: { toggleAnalysisLock() }) {
            cardIcon(locked ? "lock.fill" : "lock.open", tint: locked ? .orange : .secondary)
        }
        .help(locked
              ? "Analysis locked — click to unlock"
              : "Lock the analysis so it is never regenerated")
    }

    private var favoriteCard: some View {
        let fav = app.isFavorite
        return UtilityCard(tint: .pink, active: fav, action: { toggleFavorite() }) {
            cardIcon(fav ? "star.fill" : "star", tint: fav ? .pink : .secondary)
        }
        .help(fav ? "Favorite — click to unmark" : "Mark as favorite")
    }

    private func toggleFavorite() {
        let ensured = ensureRecord()
        ensured.isFavorite.toggle()
        viewModel.setFavorite(bundleID: app.bundleID, value: ensured.isFavorite)
        saveRecord()
    }

    private var docsCard: some View {
        let hasDocs = record?.docsEvidence?.isEmpty == false
        let enabled = app.isMyApp
        return UtilityCard(tint: .teal, active: hasDocs && enabled, disabled: !enabled, action: {
            if hasDocs { refreshDocs() } else { attachDocsFolder() }
        }) {
            cardIcon("doc.text", tint: (hasDocs && enabled) ? .teal : .secondary)
        }
        .help(enabled ? docsHelp : "Mark this as My App (the hammer) to attach a project folder")
        .contextMenu {
            if enabled {
            Button {
                attachDocsFolder()
            } label: {
                Label(hasDocs ? "Change Folder…" : "Attach Project Folder…", systemImage: "folder")
            }
            if hasDocs {
                Button {
                    refreshDocs()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                if let path = record?.docsFolderPath, !path.isEmpty {
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                    } label: {
                        Label("Reveal Source in Finder", systemImage: "magnifyingglass")
                    }
                }
                Button(role: .destructive) {
                    removeDocs()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
            }
        }
    }

    private var docsHelp: String {
        guard let evidence = record?.docsEvidence, !evidence.isEmpty else {
            return "Attach this app's project folder — Sift reads its README to ground the analysis"
        }
        let source = record?.docsFolderPath.map { " · \($0)" } ?? ""
        let snippet = evidence.replacingOccurrences(of: "\n", with: " ").prefix(80)
        return "Docs attached\(source)\n\(snippet)…"
    }

    private func attachDocsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Attach"
        panel.message = "Choose \(app.name)'s project folder (Sift reads its README and manifest)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        storeDocs(fromFolder: url.path)
    }

    private func refreshDocs() {
        guard let path = record?.docsFolderPath, !path.isEmpty else { return }
        storeDocs(fromFolder: path)
    }

    private func storeDocs(fromFolder path: String) {
        guard let evidence = DocsEvidence.extract(fromFolder: path) else {
            docsMessage = "No README or manifest found in that folder."
            return
        }
        let ensured = ensureRecord()
        let previousEvidence = ensured.docsEvidence
        let unchanged = previousEvidence?.trimmingCharacters(in: .whitespacesAndNewlines)
            == evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        ensured.docsEvidence = evidence
        ensured.docsFolderPath = path
        saveRecord()
        if !unchanged {
            viewModel.reanalyzeAfterDocsChange(bundleID: app.bundleID)
        }
    }

    private func removeDocs() {
        let ensured = ensureRecord()
        ensured.docsEvidence = nil
        ensured.docsFolderPath = nil
        saveRecord()
        viewModel.reanalyzeAfterDocsChange(bundleID: app.bundleID)
    }

    private var notesCard: some View {
        let hasNote = record?.notes?.isEmpty == false
        return UtilityCard(tint: .yellow, active: hasNote, action: { notesSheetPresented = true }) {
            cardIcon(hasNote ? "square.and.pencil" : "note.text", tint: hasNote ? .yellow : .secondary)
        }
        .help(notesHelp)
        .onDisappear {
            endNotesSession()
        }
    }

    private var notesHelp: String {
        if let notes = record?.notes, !notes.isEmpty {
            let firstLine = notes.components(separatedBy: .newlines).first ?? notes
            return "Notes: \(firstLine)"
        }
        return "Add notes — your words feed the next analysis"
    }

    private func endNotesSession() {
        guard let bundleID = notesSessionBundleID else { return }
        viewModel.reanalyzeAfterNotesChange(bundleID: bundleID,
                                            previousNotes: notesSessionInitialNotes)
        notesSessionBundleID = nil
        notesSessionInitialNotes = nil
    }

    private var moneyCard: some View {
        let state = MoneyCubeState.derive(
            isAppStoreInstall: app.isAppStoreInstall,
            hasLicenseKey: currentLicenseKey?.isEmpty == false,
            isPaidApp: record?.isPaidApp == true,
            hasSubscription: record?.hasSubscription == true,
            renewalNear: subscriptionRenewalIsNear,
            isFreeApp: record?.isFreeApp == true,
            licenseType: record?.licenseType.flatMap(LicenseType.init(rawValue:))
        )
        let disabled = UtilityCardRules.moneyDisabled(isMyApp: app.isMyApp)
        let tint = state.tint

        return UtilityCard(tint: tint, active: state.isActive, disabled: disabled, action: {
            openMoneyPopover()
        }) {
            cardIcon(state.symbol, tint: state.isActive ? tint : .secondary)
        }
        .help(moneyHelp(for: state))
        .contextMenu { moneyContextMenu }
        .popover(isPresented: $moneyPopoverPresented, arrowEdge: .bottom) {
            MoneyPopover(
                appName: app.name,
                isAppStoreInstall: app.isAppStoreInstall,
                isMyApp: app.isMyApp,
                isPaid: record?.isPaidApp == true,
                isFree: record?.isFreeApp == true,
                hasKey: currentLicenseKey?.isEmpty == false,
                hasSubscription: record?.hasSubscription == true,
                currentLicenseType: record?.licenseType.flatMap(LicenseType.init(rawValue:)),
                startOnSubscription: moneyPopoverStartsOnSubscription,
                draftLicenseKey: $draftLicenseKey,
                draftLicenseEmail: $draftLicenseEmail,
                draftLicenseType: $draftLicenseType,
                draftSubPrice: $draftSubPrice,
                draftSubCurrency: $draftSubCurrency,
                draftSubCycle: $draftSubCycle,
                draftSubRenewal: $draftSubRenewal,
                draftSubEmail: $draftSubEmail,
                onToggleFree: { toggleFree() },
                onSaveLicense: { saveLicenseFromDrafts() },
                onCopyKey: { if let key = currentLicenseKey { copyLicenseKey(key) } },
                onRemoveKey: { removeLicenseKey() },
                onSaveSubscription: { saveSubscriptionFromDrafts() },
                onRemoveSubscription: { clearSubscription() }
            )
        }
    }

    private func moneyHelp(for state: MoneyCubeState) -> String {
        switch state {
        case .subscription: return subscriptionHelp
        case .appStore, .licensed: return licenseHelp
        case .free: return "Free app — click for license details"
        case .none: return "Paid/free, license key, subscription"
        }
    }

    /// The money cube's strip line, prefixed so the cube is namable at a glance.
    private var moneyStripLabel: String {
        let state = MoneyCubeState.derive(
            isAppStoreInstall: app.isAppStoreInstall,
            hasLicenseKey: currentLicenseKey?.isEmpty == false,
            isPaidApp: record?.isPaidApp == true,
            hasSubscription: record?.hasSubscription == true,
            renewalNear: subscriptionRenewalIsNear,
            isFreeApp: record?.isFreeApp == true,
            licenseType: record?.licenseType.flatMap(LicenseType.init(rawValue:))
        )
        return "License — \(moneyHelp(for: state))"
    }

    /// Populate every draft from the record so the popover opens current.
    private func prepareMoneyDrafts() {
        draftLicenseKey = currentLicenseKey ?? ""
        draftLicenseEmail = record?.licenseEmail
            ?? UserDefaults.standard.string(forKey: "defaultLicenseEmail") ?? ""
        draftLicenseType = record?.licenseType.flatMap(LicenseType.init(rawValue:))
        draftSubPrice = record?.subscriptionPrice.map { String(format: "%.2f", $0) } ?? ""
        draftSubCurrency = record?.subscriptionCurrency
            ?? (Locale.current.currency?.identifier ?? "USD")
        draftSubCycle = BillingCycle(rawValue: record?.subscriptionCycle ?? "") ?? .monthly
        draftSubRenewal = record?.subscriptionRenewalDate ?? Date()
        draftSubEmail = record?.subscriptionEmail
            ?? record?.licenseEmail
            ?? UserDefaults.standard.string(forKey: "defaultLicenseEmail") ?? ""
    }

    private var licenseHelp: String {
        let type = record?.licenseType.flatMap(LicenseType.init(rawValue:))
        if app.isAppStoreInstall {
            if let type {
                return "Mac App Store — \(type.displayName), tied to your Apple ID"
            }
            return record?.isPaidApp == true
                ? "Mac App Store — paid, tied to your Apple ID"
                : "Mac App Store — tied to your Apple ID"
        }
        if let key = currentLicenseKey, !key.isEmpty {
            var parts = ["License key saved"]
            if let type {
                parts.append(type.displayName)
            }
            if let email = record?.licenseEmail, !email.isEmpty {
                parts.append(email)
            }
            return parts.joined(separator: " · ")
        }
        if let type {
            var parts = ["\(type.displayName) license"]
            if let email = record?.licenseEmail, !email.isEmpty {
                parts.append(email)
            }
            return parts.joined(separator: " · ")
        }
        return "Add a license key"
    }

    /// State-aware right-click: only what makes sense for this app right now.
    /// A saved key implies paid, so the Paid/Free marks show only while
    /// nothing is saved yet; App Store installs get the seal note instead.
    @ViewBuilder
    private var moneyContextMenu: some View {
        let hasSub = record?.hasSubscription == true

        if app.isAppStoreInstall {
            Label("Mac App Store — tied to your Apple ID", systemImage: "checkmark.seal.fill")
            Button {
                openMoneyPopover()
            } label: {
                Label(record?.licenseType == nil ? "Set License Type…" : "Edit License…",
                      systemImage: "pencil")
            }
        } else if let key = currentLicenseKey, !key.isEmpty {
            Button {
                copyLicenseKey(key)
            } label: {
                Label("Copy Key (Touch ID)", systemImage: "doc.on.doc")
            }
            Button {
                openMoneyPopover()
            } label: {
                Label("Edit License…", systemImage: "pencil")
            }
            Button(role: .destructive) {
                removeLicenseKey()
            } label: {
                Label("Remove Key", systemImage: "trash")
            }
        } else {
            // Paid/Free only while nothing stronger is on record.
            if !hasSub, record?.licenseType == nil {
                Button {
                    togglePaid()
                } label: {
                    Label(record?.isPaidApp == true ? "Unmark Paid" : "Mark as Paid",
                          systemImage: record?.isPaidApp == true ? "checkmark.seal.fill" : "checkmark.seal")
                }
                Button {
                    toggleFree()
                } label: {
                    Label(record?.isFreeApp == true ? "Unmark Free" : "Mark as Free App",
                          systemImage: record?.isFreeApp == true ? "gift.fill" : "gift")
                }
                Divider()
            }
            Button {
                openMoneyPopover()
            } label: {
                Label(record?.licenseType == nil ? "Add License Key…" : "Edit License…",
                      systemImage: record?.licenseType == nil ? "key.horizontal" : "pencil")
            }
        }
        if hasSub {
            Divider()
            Button {
                openMoneyPopover(onSubscription: true)
            } label: {
                Label("Edit Subscription…", systemImage: "pencil")
            }
            Button(role: .destructive) {
                clearSubscription()
            } label: {
                Label("Remove Subscription", systemImage: "trash")
            }
        }
    }

    private func openMoneyPopover(onSubscription: Bool = false) {
        prepareMoneyDrafts()
        moneyPopoverStartsOnSubscription = onSubscription
        moneyPopoverPresented = true
    }

    /// Honors the sidebar's "Add/Edit License…" request for this app.
    private func consumeLicensePopoverRequest() {
        guard viewModel.licensePopoverRequestID == app.bundleID else { return }
        viewModel.licensePopoverRequestID = nil
        openMoneyPopover()
    }

    private func copyLicenseKey(_ key: String) {
        Task { @MainActor in
            if await LicenseKeyGuard.authenticate(reason: "copy the license key for \(app.name)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key, forType: .string)
            }
        }
    }

    private func removeLicenseKey() {
        licenseKeyStore.delete(bundleID: app.bundleID)
        currentLicenseKey = nil
        record?.licenseKey = nil
        record?.hasLicenseKey = false
        record?.licenseEmail = nil
        record?.licenseType = nil
        viewModel.setLicenseType(bundleID: app.bundleID, rawValue: nil)
        saveRecord()
    }

    /// A license is worth keeping even without a key — an App Store purchase
    /// carries no key at all, but "Lifetime, bought with this Apple ID" is
    /// exactly what the vault is for. So the type and email persist on their
    /// own, and only an emptied key field clears the keychain entry.
    private func saveLicenseFromDrafts() {
        let trimmed = draftLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let ensuredRecord = ensureRecord()
        if trimmed.isEmpty {
            licenseKeyStore.delete(bundleID: app.bundleID)
        } else {
            licenseKeyStore.save(trimmed, bundleID: app.bundleID)
        }
        currentLicenseKey = trimmed.isEmpty ? nil : trimmed
        ensuredRecord.licenseKey = nil
        ensuredRecord.hasLicenseKey = !trimmed.isEmpty
        let email = draftLicenseEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        ensuredRecord.licenseEmail = email.isEmpty ? nil : email
        ensuredRecord.licenseType = draftLicenseType?.rawValue
        viewModel.setLicenseType(bundleID: app.bundleID, rawValue: ensuredRecord.licenseType)
        if (!trimmed.isEmpty || draftLicenseType != nil), ensuredRecord.iconPNG == nil {
            ensuredRecord.iconPNG = app.icon?.pngData()
        }
        saveRecord()
    }

    private var subscriptionBadgeText: String {
        guard let price = record?.subscriptionPrice else { return "Marked" }
        let cycle = BillingCycle(rawValue: record?.subscriptionCycle ?? "") ?? .monthly
        let amount = formattedPrice(price, currencyCode: record?.subscriptionCurrency
            ?? Locale.current.currency?.identifier ?? "USD")
        return "\(amount)/\(cycle.abbreviation)"
    }

    private var subscriptionRenewalIsNear: Bool {
        guard let renewal = record?.subscriptionRenewalDate else { return false }
        let cycle = BillingCycle(rawValue: record?.subscriptionCycle ?? "") ?? .monthly
        let now = Date()
        let next = SubscriptionMath.nextRenewal(from: renewal, cycle: cycle, now: now)
        return SubscriptionMath.isNear(daysUntil: SubscriptionMath.daysUntil(next, now: now))
    }

    private var subscriptionHelp: String {
        guard record?.hasSubscription == true else {
            return "Click to mark a subscription · right-click to add price & renewal"
        }
        var parts: [String] = []
        if record?.subscriptionPrice != nil {
            parts.append(subscriptionBadgeText)
        }
        if let renewal = record?.subscriptionRenewalDate {
            let cycle = BillingCycle(rawValue: record?.subscriptionCycle ?? "") ?? .monthly
            let now = Date()
            let next = SubscriptionMath.nextRenewal(from: renewal, cycle: cycle, now: now)
            parts.append(SubscriptionMath.countdownText(daysUntil: SubscriptionMath.daysUntil(next, now: now)))
        }
        if let email = record?.subscriptionEmail, !email.isEmpty {
            parts.append(email)
        }
        return parts.isEmpty ? "Subscription marked — click to add details" : parts.joined(separator: " · ")
    }

    private func saveSubscriptionFromDrafts() {
        let ensured = ensureRecord()
        ensured.subscriptionPrice = Double(draftSubPrice.replacingOccurrences(of: ",", with: "."))
        ensured.subscriptionCurrency = draftSubCurrency.isEmpty ? nil : draftSubCurrency
        ensured.subscriptionCycle = draftSubCycle.rawValue
        ensured.subscriptionRenewalDate = draftSubRenewal
        let email = draftSubEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        ensured.subscriptionEmail = email.isEmpty ? nil : email
        ensured.hasSubscription = true
        if ensured.iconPNG == nil { ensured.iconPNG = app.icon?.pngData() }
        viewModel.setSubscription(bundleID: app.bundleID, value: true)
        saveRecord()
    }

    private var linkCard: some View {
        let urlString = record?.appURL
        let hasLink = urlString?.isEmpty == false
        return UtilityCard(tint: .blue, active: hasLink, badgeDot: !hasLink && hasSuggestedLink, action: {
            if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            } else {
                draftURL = record?.appURL ?? record?.suggestedAppURL ?? ""
                editingURL = true
            }
        }) {
            cardIcon(hasLink ? linkSymbol(for: urlString) : "link", tint: hasLink ? .blue : .secondary)
        }
        .help(linkHelp)
        .contextMenu {
            Button {
                draftURL = record?.appURL ?? record?.suggestedAppURL ?? ""
                editingURL = true
            } label: {
                Label(record?.appURL != nil ? "Edit Link" : "Add Link", systemImage: "pencil")
            }
            if record?.appURL != nil {
                Button(role: .destructive) {
                    record?.appURL = nil
                    saveRecord()
                } label: {
                    Label("Remove Link", systemImage: "xmark.circle")
                }
            }
        }
    }

    private var linkHelp: String {
        if let urlString = record?.appURL, !urlString.isEmpty {
            return "Open \(urlString) — right-click to edit"
        }
        if hasSuggestedLink {
            return "Add app link (a suggestion is prefilled)"
        }
        return "Add app link"
    }

    private var hasSuggestedLink: Bool {
        guard let suggested = record?.suggestedAppURL else { return false }
        return !suggested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private func togglePaid() {
        let ensured = ensureRecord()
        PricingMarks.setPaid(ensured, to: !ensured.isPaidApp)
        // Paid apps enter the License Vault — capture the icon so the vault
        // row has a face even after the app is uninstalled.
        if ensured.isPaidApp, ensured.iconPNG == nil {
            ensured.iconPNG = app.icon?.pngData()
        }
        viewModel.setPaidApp(bundleID: app.bundleID, value: ensured.isPaidApp)
        viewModel.setFreeApp(bundleID: app.bundleID, value: ensured.isFreeApp)
        saveRecord()
    }

    private func toggleFree() {
        let ensured = ensureRecord()
        PricingMarks.setFree(ensured, to: !ensured.isFreeApp)
        viewModel.setPaidApp(bundleID: app.bundleID, value: ensured.isPaidApp)
        viewModel.setFreeApp(bundleID: app.bundleID, value: ensured.isFreeApp)
        saveRecord()
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
        // Re-fetch rather than trusting our own stale nil — an analysis may have
        // created the record since this view loaded.
        let found = CacheService(context: modelContext).ensureRecord(bundleID: app.bundleID, appName: app.name)
        record = found
        return found
    }

    private func clearSubscription() {
        let ensured = ensureRecord()
        ensured.subscriptionPrice = nil
        ensured.subscriptionCurrency = nil
        ensured.subscriptionCycle = nil
        ensured.subscriptionRenewalDate = nil
        ensured.subscriptionEmail = nil
        ensured.hasSubscription = false
        viewModel.setSubscription(bundleID: app.bundleID, value: false)
        saveRecord()
    }

    private func formattedPrice(_ amount: Double, currencyCode: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        return f.string(from: NSNumber(value: amount))
            ?? String(format: "%.2f %@", amount, currencyCode)
    }

    // MARK: - Utility cube helpers

    /// The utility cube's icon — the cube itself is the tinted chip, so the
    /// icon renders directly at full size.
    private func cardIcon(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(pastelize(tint, colorScheme))
    }

    /// SF Symbol for a link cube, chosen from the destination host: a code
    /// glyph for source hosts (SF Symbols has no brand logos), a globe for
    /// everything else, and a plain link when there is nothing yet.
    private func linkSymbol(for urlString: String?) -> String {
        guard let urlString, !urlString.isEmpty,
              let host = URL(string: urlString)?.host()?.lowercased() else {
            return "link"
        }
        let codeHosts = ["github.com", "gitlab.com", "bitbucket.org", "codeberg.org", "sr.ht"]
        if codeHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return "chevron.left.forwardslash.chevron.right"
        }
        return "globe"
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
        case .sparkle: return "arrow.down.circle.fill"
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

struct NotesSheet: View {
    let appName: String
    @Binding var text: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes for \(appName)")
                .font(.headline)
            Text("Your words feed the next analysis — say how you actually use this app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            NotesEditor(text: $text)
                .frame(minHeight: 140)
            HStack {
                Button("Clear") {
                    text = ""
                    onClose()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove the note and close")
                Spacer()
                Button("Save") { onClose() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .help("Save and re-analyze with this note (⌘↩)")
            }
        }
        .padding(20)
        .frame(width: 440)
        .onExitCommand { onClose() }
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

/// Tint-filled cube for the utility row — the card IS the colored chip:
/// icon plus at most one badge, hugging its content. Disabled cards stay
/// visible but ignore the primary tap; the context menu stays reachable
/// (that is how Paid/Free marks remain available on a grayed card).
/// Softens a tint for dark mode — blends it toward white so the utility cubes
/// read as gentle pastels on a dark background instead of harsh saturated dots.
/// Light mode is returned unchanged.
func pastelize(_ color: Color, _ scheme: ColorScheme) -> Color {
    guard scheme == .dark else { return color }
    #if canImport(AppKit)
    guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return color }
    return Color(ns.blended(withFraction: 0.34, of: .white) ?? ns)
    #else
    return color
    #endif
}


struct UtilityCard<Content: View>: View {
    var tint: Color
    /// Filled with `tint` when active; a neutral gray square when not.
    var active: Bool = false
    var disabled: Bool = false
    /// A small dot in the corner — used to flag an available suggestion.
    var badgeDot: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    @State private var hovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var fill: Color {
        if disabled { return Color.secondary.opacity(0.06) }
        if active { return pastelize(tint, colorScheme).opacity(hovered && action != nil ? 0.22 : 0.14) }
        return Color.secondary.opacity(hovered && action != nil ? 0.12 : 0.07)
    }

    var body: some View {
        content()
            .frame(width: 34, height: 34)
            .background(fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if badgeDot {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                        .padding(4)
                }
            }
            .opacity(disabled ? 0.55 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                if !disabled { action?() }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    hovered = hovering
                }
            }
    }
}
