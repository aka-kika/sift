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
    @State private var draftLicenseEmail = ""
    @State private var draftLicenseType: LicenseType? = nil
    @State private var currentLicenseKey: String? = nil
    @State private var notesSheetPresented = false
    @State private var notesSessionBundleID: String? = nil
    @State private var notesSessionInitialNotes: String? = nil
    @State private var similarResults: [SimilarApp]? = nil
    @State private var findingSimilar = false
    @State private var editingSubscription = false
    @State private var draftSubPrice = ""
    @State private var draftSubCurrency = ""
    @State private var draftSubCycle: BillingCycle = .monthly
    @State private var draftSubRenewal = Date()
    @State private var draftSubEmail = ""
    @State private var confirmingHomebrewUpdate = false
    @State private var runningHomebrewUpdate = false
    @State private var homebrewUpdateMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                Divider()
                utilitySection
                whatIsThisSection
                recommendationSection
                improveAnalysisCallout
                if case .loaded = app.aiState {
                    similarSection
                }
            }
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
            DetailLicenseKeySheet(appName: app.name, draft: $draftLicenseKey, emailDraft: $draftLicenseEmail, licenseType: $draftLicenseType) { saved in
                if saved {
                    let trimmed = draftLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ensuredRecord = ensureRecord()
                    licenseKeyStore.save(trimmed, bundleID: app.bundleID)
                    currentLicenseKey = trimmed.isEmpty ? nil : trimmed
                    ensuredRecord.licenseKey = nil
                    ensuredRecord.hasLicenseKey = !trimmed.isEmpty
                    let email = draftLicenseEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                    ensuredRecord.licenseEmail = (trimmed.isEmpty || email.isEmpty) ? nil : email
                    ensuredRecord.licenseType = draftLicenseType?.rawValue
                    if !trimmed.isEmpty, ensuredRecord.iconPNG == nil {
                        ensuredRecord.iconPNG = app.icon?.pngData()
                    }
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
        .sheet(isPresented: $editingSubscription) {
            SubscriptionSheet(
                appName: app.name,
                price: $draftSubPrice,
                currency: $draftSubCurrency,
                cycle: $draftSubCycle,
                renewal: $draftSubRenewal,
                email: $draftSubEmail
            ) { action in
                switch action {
                case .cancel:
                    break
                case .save:
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
                case .clear:
                    clearSubscription()
                }
                editingSubscription = false
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
                    if let categoryName = AppCategory.humanName(for: app.category) {
                        Text("· \(categoryName)")
                            .font(.callout)
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
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .imageScale(.small)
        .symbolRenderingMode(.hierarchical)
        .fixedSize()
        .help("More actions")
    }

    // MARK: - Recommendation (ranking first)

    @ViewBuilder
    private var recommendationSection: some View {
        switch app.aiState {
        case .loaded(_, let score, let reason, let bestUse):
            VStack(alignment: .leading, spacing: 12) {
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

    // MARK: - Utility cards

    private var utilitySection: some View {
        HStack(alignment: .top, spacing: 12) {
            notesCard
            licenseCard
            subscriptionCard
            linkCard
            lockCard
            favoriteCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
            } else {
                Button { runFindSimilar() } label: {
                    Label("Find similar apps you have", systemImage: "square.on.square")
                }
                .buttonStyle(.bordered)
            }
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

    private var licenseCard: some View {
        let isFree = record?.isFreeApp == true
        let disabled = UtilityCardRules.licenseDisabled(isMyApp: app.isMyApp, isFreeApp: isFree)
        let licenseType = record?.licenseType.flatMap(LicenseType.init(rawValue:))
        let hasKey = currentLicenseKey?.isEmpty == false
        let openEditor: (() -> Void)? = app.isAppStoreInstall ? nil : {
            draftLicenseKey = currentLicenseKey ?? ""
            draftLicenseEmail = record?.licenseEmail
                ?? UserDefaults.standard.string(forKey: "defaultLicenseEmail") ?? ""
            draftLicenseType = licenseType
            editingLicenseKey = true
        }

        let isPaid = record?.isPaidApp == true
        let tint: Color = app.isAppStoreInstall ? .blue : .indigo
        let active = !disabled && (app.isAppStoreInstall || hasKey || isPaid || licenseType != nil)
        let symbol = app.isAppStoreInstall ? "checkmark.seal.fill" : "key.horizontal"

        return UtilityCard(tint: tint, active: active, disabled: disabled, action: openEditor) {
            cardIcon(symbol, tint: active ? tint : .secondary)
        }
        .help(licenseHelp)
        .contextMenu { licenseContextMenu }
    }

    private var licenseHelp: String {
        if app.isAppStoreInstall {
            return record?.isPaidApp == true
                ? "Mac App Store — paid, tied to your Apple ID"
                : "Mac App Store — tied to your Apple ID"
        }
        if let key = currentLicenseKey, !key.isEmpty {
            var parts = ["License key saved"]
            if let type = record?.licenseType.flatMap(LicenseType.init(rawValue:)) {
                parts.append(type.displayName)
            }
            if let email = record?.licenseEmail, !email.isEmpty {
                parts.append(email)
            }
            return parts.joined(separator: " · ")
        }
        return "Add a license key"
    }

    @ViewBuilder
    private var licenseContextMenu: some View {
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
        if let key = currentLicenseKey, !key.isEmpty {
            Divider()
            Button {
                copyLicenseKey(key)
            } label: {
                Label("Copy Key (Touch ID)", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                removeLicenseKey()
            } label: {
                Label("Remove Key", systemImage: "trash")
            }
        }
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
        saveRecord()
    }

    private var subscriptionCard: some View {
        let isFree = record?.isFreeApp == true
        let licenseType = record?.licenseType.flatMap(LicenseType.init(rawValue:))
        let disabled = UtilityCardRules.subscriptionDisabled(isMyApp: app.isMyApp, isFreeApp: isFree, licenseType: licenseType)
        let hasSub = record?.hasSubscription == true
        let active = !disabled && hasSub
        let tint: Color = subscriptionRenewalIsNear ? .orange : .green

        return UtilityCard(tint: tint, active: active, disabled: disabled, action: {
            // Fast path: a tap just flags "this has a subscription". Price and
            // renewal are optional, added from the right-click menu.
            if hasSub {
                beginEditingSubscription()
            } else {
                markSubscription()
            }
        }) {
            cardIcon(hasSub ? "creditcard.fill" : "creditcard", tint: active ? tint : .secondary)
        }
        .help(subscriptionHelp)
        .contextMenu {
            Button {
                beginEditingSubscription()
            } label: {
                Label(hasSub ? "Edit Price & Renewal…" : "Add Price & Renewal…", systemImage: "pencil")
            }
            if hasSub {
                Button(role: .destructive) {
                    clearSubscription()
                } label: {
                    Label("Remove Subscription", systemImage: "trash")
                }
            }
        }
    }

    /// Flags a subscription without any details — the one-click path.
    private func markSubscription() {
        let ensured = ensureRecord()
        ensured.hasSubscription = true
        if ensured.iconPNG == nil { ensured.iconPNG = app.icon?.pngData() }
        viewModel.setSubscription(bundleID: app.bundleID, value: true)
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
        viewModel.setPaidApp(bundleID: app.bundleID, value: ensured.isPaidApp)
        saveRecord()
    }

    private func toggleFree() {
        let ensured = ensureRecord()
        PricingMarks.setFree(ensured, to: !ensured.isFreeApp)
        viewModel.setPaidApp(bundleID: app.bundleID, value: ensured.isPaidApp)
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

    private func beginEditingSubscription() {
        draftSubPrice = record?.subscriptionPrice.map { String(format: "%.2f", $0) } ?? ""
        draftSubCurrency = record?.subscriptionCurrency
            ?? (Locale.current.currency?.identifier ?? "USD")
        draftSubCycle = BillingCycle(rawValue: record?.subscriptionCycle ?? "") ?? .monthly
        draftSubRenewal = record?.subscriptionRenewalDate ?? Date()
        draftSubEmail = record?.subscriptionEmail
            ?? record?.licenseEmail
            ?? UserDefaults.standard.string(forKey: "defaultLicenseEmail") ?? ""
        editingSubscription = true
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
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
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

struct DetailLicenseKeySheet: View {
    let appName: String
    @Binding var draft: String
    @Binding var emailDraft: String
    @Binding var licenseType: LicenseType?
    let onDone: (Bool) -> Void

    @FocusState private var focused: Bool
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("License key for \(appName)")
                .font(.headline)
            Text("Store the purchased key for this app so you can copy it later.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Group {
                    if revealed {
                        TextField("Enter license key", text: $draft)
                    } else {
                        SecureField("Enter license key", text: $draft)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .focused($focused)

                Button {
                    if revealed {
                        revealed = false
                    } else {
                        Task { @MainActor in
                            if await LicenseKeyGuard.authenticate(reason: "reveal the license key for \(appName)") {
                                revealed = true
                            }
                        }
                    }
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(revealed ? "Hide license key" : "Reveal license key (Touch ID)")
            }

            TextField("Registered email (optional)", text: $emailDraft)
                .textFieldStyle(.roundedBorder)

            Picker("License type", selection: $licenseType) {
                Text("Not set").tag(LicenseType?.none)
                ForEach(LicenseType.allCases) { type in
                    Text(type.displayName).tag(LicenseType?.some(type))
                }
            }
            .pickerStyle(.menu)

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

// MARK: - Subscription Sheet

enum SubscriptionSheetAction { case cancel, save, clear }

struct SubscriptionSheet: View {
    let appName: String
    @Binding var price: String
    @Binding var currency: String
    @Binding var cycle: BillingCycle
    @Binding var renewal: Date
    @Binding var email: String
    let onDone: (SubscriptionSheetAction) -> Void

    @FocusState private var focused: Bool

    private static let currencies = ["USD", "EUR", "GBP", "ILS", "CAD", "AUD", "JPY", "CHF"]

    /// Always include the record's current currency even if it is not in the
    /// short list, so the picker can display it without losing the value.
    static func currencyOptions(including current: String) -> [String] {
        if current.isEmpty || currencies.contains(current) { return currencies }
        return [current] + currencies
    }

    private var parsedAmount: Double? {
        Double(price.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subscription for \(appName)")
                .font(.headline)
            Text("Track what you pay and when it renews next.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Amount", text: $price)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                    .focused($focused)
                Picker("", selection: $currency) {
                    ForEach(Self.currencyOptions(including: currency), id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 110)
            }

            Picker("Billing", selection: $cycle) {
                ForEach(BillingCycle.allCases) { c in
                    Text(c.label).tag(c)
                }
            }
            .pickerStyle(.segmented)

            DatePicker("Next renewal", selection: $renewal, displayedComponents: .date)

            TextField("Billing email (optional)", text: $email)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { onDone(.cancel) }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Clear") { onDone(.clear) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button("Save") { onDone(.save) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedAmount == nil)
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

/// Tint-filled cube for the utility row — the card IS the colored chip:
/// icon plus at most one badge, hugging its content. Disabled cards stay
/// visible but ignore the primary tap; the context menu stays reachable
/// (that is how Paid/Free marks remain available on a grayed card).
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

    private var fill: Color {
        if disabled { return Color.secondary.opacity(0.08) }
        if active { return tint.opacity(hovered && action != nil ? 0.24 : 0.15) }
        return Color.secondary.opacity(hovered && action != nil ? 0.14 : 0.09)
    }

    var body: some View {
        VStack(spacing: 6, content: content)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if badgeDot {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                        .padding(7)
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
