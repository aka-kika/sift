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
    @State private var currentLicenseKey: String? = nil
    @State private var notesExpanded = false
    @State private var notesHovered = false
    @State private var licenseHovered = false
    @State private var urlHovered = false
    @State private var subHovered = false
    @State private var editingSubscription = false
    @State private var draftSubPrice = ""
    @State private var draftSubCurrency = ""
    @State private var draftSubCycle: BillingCycle = .monthly
    @State private var draftSubRenewal = Date()
    @State private var draftSubEmail = ""
    @State private var confirmingHomebrewUpdate = false
    @State private var runningHomebrewUpdate = false
    @State private var homebrewUpdateMessage: String? = nil
    @State private var isKeyRevealed = false
    @State private var keyCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                Divider()
                whatIsThisSection
                recommendationSection
                improveAnalysisCallout
                utilitySection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .softTopScrollEdge()
        .navigationTitle(app.name)
        .task(id: app.bundleID) {
            loadRecord()
            loadLicenseKey()
            isKeyRevealed = false
            keyCopied = false
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
            DetailLicenseKeySheet(appName: app.name, draft: $draftLicenseKey, emailDraft: $draftLicenseEmail) { saved in
                if saved {
                    let trimmed = draftLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ensuredRecord = ensureRecord()
                    licenseKeyStore.save(trimmed, bundleID: app.bundleID)
                    currentLicenseKey = trimmed.isEmpty ? nil : trimmed
                    ensuredRecord.licenseKey = nil
                    ensuredRecord.hasLicenseKey = !trimmed.isEmpty
                    let email = draftLicenseEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                    ensuredRecord.licenseEmail = (trimmed.isEmpty || email.isEmpty) ? nil : email
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
            UtilityRowDivider()
            licenseKeySection
            UtilityRowDivider()
            subscriptionSection
            UtilityRowDivider()
            urlSection
        }
        .padding(.horizontal, 12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                utilityChip("note.text", tint: .yellow)
                Text("Notes")
                    .font(.subheadline.weight(.medium))
                if let notes = record?.notes, !notes.isEmpty {
                    Text("Saved")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("None yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        notesExpanded.toggle()
                    }
                } label: {
                    Image(systemName: (record?.notes?.isEmpty == false) ? "pencil" : "plus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help((record?.notes?.isEmpty == false) ? "Edit notes" : "Add notes")
                .opacity(notesHovered ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    notesExpanded.toggle()
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    notesHovered = hovering
                }
            }

            if notesExpanded {
                NotesEditor(
                    text: Binding(
                        get: { record?.notes ?? "" },
                        set: { ensureRecord().notes = $0.isEmpty ? nil : $0; saveRecord() }
                    )
                )
                .padding(.top, 8)
            }
        }
        .onChange(of: app.bundleID) { _, _ in
            notesExpanded = false
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var licenseKeySection: some View {
        Group {
            if app.isAppStoreInstall {
                appStoreOwnershipRowContent
            } else {
                licenseKeyRowContent
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                licenseHovered = hovering
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appStoreOwnershipRowContent: some View {
        HStack(spacing: 8) {
            utilityChip("bag.fill", tint: .blue)
            Text("Mac App Store")
                .font(.subheadline.weight(.medium))
            Text("Tied to your Apple ID")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if record?.isPaidApp == true {
                Text("Paid")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.14), in: Capsule())
            }
            Spacer()
            Button {
                togglePaidApp()
            } label: {
                Image(systemName: record?.isPaidApp == true ? "checkmark.seal.fill" : "checkmark.seal")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(record?.isPaidApp == true ? "Marked as paid — click to unmark" : "Mark as paid")
            .opacity(licenseHovered ? 1 : 0)
        }
    }

    private var licenseKeyRowContent: some View {
        HStack(spacing: 8) {
            utilityChip("key.horizontal", tint: .indigo)
            Text("License Key")
                .font(.subheadline.weight(.medium))
            if let licenseKey = currentLicenseKey, !licenseKey.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isKeyRevealed ? licenseKey : maskedLicenseKey(licenseKey))
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .textSelection(.enabled)
                    if let email = record?.licenseEmail, !email.isEmpty {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else {
                Text("None yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if keyCopied {
                Text("Copied")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Group {
                if let licenseKey = currentLicenseKey, !licenseKey.isEmpty {
                    Button {
                        if isKeyRevealed {
                            isKeyRevealed = false
                        } else {
                            Task { @MainActor in
                                if await LicenseKeyGuard.authenticate(reason: "reveal the license key for \(app.name)") {
                                    isKeyRevealed = true
                                    try? await Task.sleep(for: .seconds(10))
                                    isKeyRevealed = false
                                }
                            }
                        }
                    } label: {
                        Image(systemName: isKeyRevealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(isKeyRevealed ? "Hide license key" : "Reveal license key (Touch ID)")

                    Button {
                        Task { @MainActor in
                            if await LicenseKeyGuard.authenticate(reason: "copy the license key for \(app.name)") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(licenseKey, forType: .string)
                                keyCopied = true
                                try? await Task.sleep(for: .seconds(1.5))
                                keyCopied = false
                            }
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Copy license key (Touch ID)")
                }
                Button {
                    draftLicenseKey = currentLicenseKey ?? ""
                    draftLicenseEmail = record?.licenseEmail
                        ?? UserDefaults.standard.string(forKey: "defaultLicenseEmail") ?? ""
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
                        isKeyRevealed = false
                        record?.licenseKey = nil
                        record?.hasLicenseKey = false
                        record?.licenseEmail = nil
                        saveRecord()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove license key")
                }
            }
            .opacity(licenseHovered ? 1 : 0)
        }
    }

    private var subscriptionSection: some View {
        HStack(spacing: 8) {
            utilityChip("creditcard", tint: .green)
            Text("Subscription")
                .font(.subheadline.weight(.medium))
            if record?.hasSubscription == true, let renewal = record?.subscriptionRenewalDate {
                subscriptionDetailLine(renewal: renewal)
            } else if record?.hasSubscription == true {
                Text("Marked · add details")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("None yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Group {
                Button {
                    beginEditingSubscription()
                } label: {
                    Image(systemName: record?.hasSubscription == true ? "pencil" : "plus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(record?.hasSubscription == true ? "Edit subscription" : "Add subscription")

                if record?.hasSubscription == true {
                    Button(role: .destructive) {
                        clearSubscription()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove subscription")
                }
            }
            .opacity(subHovered ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                subHovered = hovering
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The price + countdown (+ optional email) shown when a subscription has a
    /// renewal date. A plain function (not a ViewBuilder property) so it can use
    /// `let` bindings for the math before returning the view.
    private func subscriptionDetailLine(renewal: Date) -> some View {
        let cycle = BillingCycle(rawValue: record?.subscriptionCycle ?? "") ?? .monthly
        let now = Date()
        let next = SubscriptionMath.nextRenewal(from: renewal, cycle: cycle, now: now)
        let days = SubscriptionMath.daysUntil(next, now: now)
        let countdownStyle: AnyShapeStyle = SubscriptionMath.isNear(daysUntil: days)
            ? AnyShapeStyle(.orange)
            : AnyShapeStyle(.secondary)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let price = record?.subscriptionPrice {
                    Text(formattedPrice(price, currencyCode: record?.subscriptionCurrency
                        ?? Locale.current.currency?.identifier ?? "USD"))
                        .font(.body)
                    Text("/ \(cycle.abbreviation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("· " + SubscriptionMath.countdownText(daysUntil: days))
                    .font(.caption)
                    .foregroundStyle(countdownStyle)
            }
            if let email = record?.subscriptionEmail, !email.isEmpty {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var urlSection: some View {
        HStack(spacing: 8) {
            utilityChip("link", tint: .blue)
            Text("App Link")
                .font(.subheadline.weight(.medium))
            if let urlString = record?.appURL, !urlString.isEmpty,
               let url = URL(string: urlString) {
                Link(urlString, destination: url)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if hasSuggestedLink {
                Text("None yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("· suggestion available")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("None yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Group {
                Button {
                    draftURL = record?.appURL ?? record?.suggestedAppURL ?? ""
                    editingURL = true
                } label: {
                    Image(systemName: record?.appURL != nil ? "pencil" : "plus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(record?.appURL != nil ? "Edit app link" : (hasSuggestedLink ? "Add app link (a suggestion is prefilled)" : "Add app link"))
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
            .opacity(urlHovered ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                urlHovered = hovering
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func togglePaidApp() {
        let ensured = ensureRecord()
        ensured.isPaidApp.toggle()
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

    private func maskedLicenseKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed }
        return "\(trimmed.prefix(4))••••\(trimmed.suffix(4))"
    }

    // MARK: - Utility chip

    /// Tinted icon chip used by the utility rows — the same visual language as
    /// System Settings list icons.
    private func utilityChip(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
    @Binding var emailDraft: String
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

            TextField("Registered email (optional)", text: $emailDraft)
                .textFieldStyle(.roundedBorder)

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

private struct UtilityRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 36)
    }
}
