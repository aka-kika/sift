import SwiftUI
import SwiftData

#if canImport(AppKit)
import AppKit
#endif

struct AppRow: View {
    let app: AppInfo
    @AppStorage("developerMode") private var developerMode = false
    @Environment(\.modelContext) private var modelContext
    @Environment(AppListViewModel.self) private var viewModel
    private let licenseKeyStore = LicenseKeyStore.shared
    @State private var uninstallSheetPresented = false
    @State private var homebrewCommandCopied = false

    var body: some View {
        HStack(spacing: 10) {
            #if canImport(AppKit)
            if let sendableIcon = app.icon {
                Image(nsImage: sendableIcon.image)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 32, height: 32)
            }
            #endif

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(app.name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if app.isRunning {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .help("Open now")
                    }
                    if app.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if DevModeRules.showsMyAppUI(isMyApp: app.isMyApp, developerMode: developerMode) {
                        Image(systemName: "hammer.fill")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    if licenseBadgeState != .none {
                        Image(systemName: licenseBadgeState.symbol)
                            .font(.caption2)
                            .foregroundStyle(licenseBadgeState.tint)
                            .help(licenseBadgeHelp)
                    }
                    if app.isAnalysisLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if case .updateAvailable(let latestVersion, let source, _) = app.updateState {
                        UpdateBadgeView(latestVersion: latestVersion, source: source)
                    }
                }
                Text(subtitleText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            if viewModel.sortOrder == .updates,
               case .updateAvailable(let latestVersion, let source, _) = app.updateState {
                HStack(spacing: 4) {
                    if source == .homebrew && homebrewCommandCopied {
                        Text("Command copied")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button {
                        performUpdateAction(source: source)
                    } label: {
                        Image(systemName: updateActionIcon(source: source))
                            .font(.caption)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
                    .help(updateActionHelp(latestVersion: latestVersion, source: source))
                    .accessibilityLabel(updateActionAccessibilityLabel(latestVersion: latestVersion, source: source))
                }
            }

            ScoreBadgeView(state: app.aiState, isMyApp: DevModeRules.showsMyAppUI(isMyApp: app.isMyApp, developerMode: developerMode))
        }
        .padding(.vertical, 2)
        .contextMenu {
            // Group 1: Analysis actions
            Button {
                Task { await viewModel.reanalyze(bundleID: app.bundleID) }
            } label: {
                Label("Re-analyze", systemImage: "arrow.clockwise")
            }
            .disabled(app.isAnalysisLocked)

            Button {
                toggleAnalysisLock()
            } label: {
                if app.isAnalysisLocked {
                    Label("Unlock Analysis", systemImage: "lock.open")
                } else {
                    Label("Lock Analysis", systemImage: "lock.fill")
                }
            }

            Divider()

            // Group 2: Favorites / My App / Subscription toggles
            Button {
                toggleFavorite()
            } label: {
                if app.isFavorite {
                    Label("Remove from Favorites", systemImage: "star.slash")
                } else {
                    Label("Add to Favorites", systemImage: "star")
                }
            }

            if developerMode {
                Button {
                    toggleMyApp()
                } label: {
                    if app.isMyApp {
                        Label("Unmark as My App", systemImage: "hammer.slash")
                    } else {
                        Label("Mark as My App", systemImage: "hammer.fill")
                    }
                }
            }

            Divider()

            // Group 3: one License entry — everything money lives in the
            // detail view's License popover. App Store installs get it too:
            // the seal says where it came from, not what kind of purchase it
            // was, and that is the part worth recording.
            if let licenseKey = existingLicenseKey {
                Button {
                    Task { @MainActor in
                        if await LicenseKeyGuard.authenticate(reason: "copy the license key for \(app.name)") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(licenseKey, forType: .string)
                        }
                    }
                } label: {
                    Label("Copy Key", systemImage: "doc.on.doc")
                }
                Button {
                    requestLicensePopover()
                } label: {
                    Label("Edit License…", systemImage: "pencil")
                }
            } else if app.licenseType != nil {
                Button {
                    requestLicensePopover()
                } label: {
                    Label("Edit License…", systemImage: "pencil")
                }
            } else {
                Button {
                    requestLicensePopover()
                } label: {
                    Label(app.isAppStoreInstall ? "Set License Type…" : "Add License…",
                          systemImage: app.isAppStoreInstall ? "checkmark.seal" : "key.horizontal")
                }
            }

            Divider()

            // Group 4: Show in Finder, Open App, update items
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
            if case .updateAvailable(let latestVersion, let source, _) = app.updateState {
                Button {
                    performUpdateAction(source: source)
                } label: {
                    Label(updateActionTitle(latestVersion: latestVersion, source: source), systemImage: updateActionIcon(source: source))
                }

                Button {
                    viewModel.acknowledgeUpdate(bundleID: app.bundleID, updateState: app.updateState)
                } label: {
                    Label("Mark Updated", systemImage: "checkmark.circle")
                }
            }

            Divider()

            // Group 5: Copy Bundle ID
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.bundleID, forType: .string)
            } label: {
                Label("Copy Bundle ID", systemImage: "doc.on.doc")
            }

            // Group 6: Uninstall — never for Apple system apps or Sift itself.
            if !UninstallRules.isProtected(bundleID: app.bundleID) {
                Divider()
                Button(role: .destructive) {
                    uninstallSheetPresented = true
                } label: {
                    Label("Uninstall…", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $uninstallSheetPresented) {
            UninstallSheet(app: app) { removedBundle in
                if removedBundle {
                    viewModel.removeApp(bundleID: app.bundleID)
                }
                uninstallSheetPresented = false
            }
        }
    }

    /// Selects the app and asks the detail view to open its License popover.
    private func requestLicensePopover() {
        viewModel.selectedAppID = app.bundleID
        viewModel.licensePopoverRequestID = app.bundleID
    }

    private var subtitleText: String {
        let base = app.version.isEmpty ? app.bundleID : app.version
        guard viewModel.sortOrder == .lastUsed else { return base }
        return "\(base) · \(lastUsedText)"
    }

    private var lastUsedText: String {
        guard let date = app.lastUsedDate else { return "Never used" }
        return "Used " + Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private func toggleFavorite() {
        let bundleID = app.bundleID
        let descriptor = FetchDescriptor<AppRecord>(predicate: #Predicate { $0.bundleID == bundleID })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.isFavorite.toggle()
            try? modelContext.save()
            viewModel.setFavorite(bundleID: bundleID, value: existing.isFavorite)
        } else {
            let rec = AppRecord(
                bundleID: bundleID,
                appName: app.name,
                explanation: "",
                relevanceScore: 0,
                relevanceReason: "",
                bestUse: "",
                ollamaModel: ""
            )
            rec.isFavorite = true
            modelContext.insert(rec)
            try? modelContext.save()
            viewModel.setFavorite(bundleID: bundleID, value: true)
        }
    }

    private func toggleMyApp() {
        let bundleID = app.bundleID
        let descriptor = FetchDescriptor<AppRecord>(predicate: #Predicate { $0.bundleID == bundleID })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.isMyApp.toggle()
            try? modelContext.save()
            viewModel.setMyApp(bundleID: bundleID, value: existing.isMyApp)
        } else {
            // No AI record yet — create a stub just to hold the flag
            let rec = AppRecord(
                bundleID: bundleID,
                appName: app.name,
                explanation: "",
                relevanceScore: 0,
                relevanceReason: "",
                bestUse: "",
                ollamaModel: ""
            )
            rec.isMyApp = true
            modelContext.insert(rec)
            try? modelContext.save()
            viewModel.setMyApp(bundleID: bundleID, value: true)
        }
    }

    private func toggleAnalysisLock() {
        let record = fetchRecord(for: app.bundleID) ?? {
            let record = makeStubRecord()
            modelContext.insert(record)
            return record
        }()

        record.isAnalysisLocked.toggle()
        try? modelContext.save()
        viewModel.setAnalysisLocked(bundleID: app.bundleID, value: record.isAnalysisLocked)
    }

    private var existingLicenseKey: String? {
        resolveLicenseKey().value
    }

    /// The row's license badge mirrors the detail view's License cube — same
    /// derivation, same symbol, same tint, so a state reads identically in
    /// both places. Renewal proximity is a detail-view concern only.
    private var licenseBadgeState: MoneyCubeState {
        MoneyCubeState.derive(
            isAppStoreInstall: app.isAppStoreInstall,
            hasLicenseKey: existingLicenseKey != nil,
            isPaidApp: app.isPaidApp,
            hasSubscription: app.isSubscribed,
            renewalNear: false,
            isFreeApp: app.isFreeApp,
            licenseType: app.licenseType
        )
    }

    private var licenseBadgeHelp: String {
        switch licenseBadgeState {
        case .subscription: return "Subscription"
        case .appStore: return "Mac App Store — tied to your Apple ID"
        case .licensed(let type): return type.map { "\($0.displayName) license" } ?? "License key saved"
        case .free: return "Free app"
        case .none: return ""
        }
    }

    private func resolveLicenseKey() -> LicenseKeyResolution {
        let record = fetchRecord(for: app.bundleID)
        let resolution = licenseKeyStore.resolveKey(bundleID: app.bundleID, legacyValue: record?.licenseKey)
        if resolution.didMigrateLegacyValue, let record {
            record.licenseKey = nil
            try? modelContext.save()
        }
        return resolution
    }

    private func fetchRecord(for bundleID: String) -> AppRecord? {
        let descriptor = FetchDescriptor<AppRecord>(predicate: #Predicate { $0.bundleID == bundleID })
        return try? modelContext.fetch(descriptor).first
    }

    private func makeStubRecord() -> AppRecord {
        AppRecord(
            bundleID: app.bundleID,
            appName: app.name,
            explanation: "",
            relevanceScore: 0,
            relevanceReason: "",
            bestUse: "",
            ollamaModel: ""
        )
    }

    private func performUpdateAction(source: AppInfo.UpdateSource) {
        switch source {
        case .appStore, .sparkle:
            if let updateURL = app.updateState.actionURL {
                NSWorkspace.shared.open(updateURL)
            }
        case .homebrew:
            guard let command = app.homebrewUpdateCommand else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            showHomebrewCopiedConfirmation()
        }
    }

    private func showHomebrewCopiedConfirmation() {
        homebrewCommandCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                homebrewCommandCopied = false
            }
        }
    }

    private func updateActionIcon(source: AppInfo.UpdateSource) -> String {
        switch source {
        case .appStore:
            return "bag.fill"
        case .sparkle:
            return "arrow.down.circle.fill"
        case .homebrew:
            return "terminal.fill"
        }
    }

    private func updateActionTitle(latestVersion: String, source: AppInfo.UpdateSource) -> String {
        switch source {
        case .appStore:
            return "Open in App Store (\(latestVersion))"
        case .sparkle:
            return "Open Download (\(latestVersion))"
        case .homebrew:
            return "Copy Brew Command (\(latestVersion))"
        }
    }

    private func updateActionHelp(latestVersion: String, source: AppInfo.UpdateSource) -> String {
        switch source {
        case .appStore:
            return "Open \(app.name) in the App Store to update to \(latestVersion)."
        case .sparkle:
            return "Open \(app.name)'s download page for \(latestVersion)."
        case .homebrew:
            return "Copy \(app.homebrewUpdateCommand ?? "brew upgrade --cask ...")"
        }
    }

    private func updateActionAccessibilityLabel(latestVersion: String, source: AppInfo.UpdateSource) -> String {
        switch source {
        case .appStore:
            return "Open \(app.name) in App Store, version \(latestVersion)"
        case .sparkle:
            return "Open \(app.name) download, version \(latestVersion)"
        case .homebrew:
            return "Copy Homebrew update command for \(app.name), version \(latestVersion)"
        }
    }
}

private struct UpdateBadgeView: View {
    let latestVersion: String
    let source: AppInfo.UpdateSource

    var body: some View {
        Text("\(source.badgeLabel) \(latestVersion)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.12), in: Capsule())
    }
}

private extension AppInfo.UpdateSource {
    var badgeLabel: String {
        switch self {
        case .appStore:
            return "Store"
        case .sparkle:
            return "Sparkle"
        case .homebrew:
            return "Brew"
        }
    }
}

struct ScoreBadgeView: View {
    let state: AppInfo.AIState
    var isMyApp: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch state {
        case .pending:
            if isMyApp {
                Image(systemName: "hammer.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .frame(width: 24, height: 24)
            } else {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 24, height: 24)
            }
        case .loading:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 24, height: 24)
        case .loaded(_, let score, _, _):
            ZStack {
                Text("\(score)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(numeralColor(score))
                    .frame(width: 24, height: 24)
                    .background(pastelize(scoreColor(score), colorScheme), in: Circle())
                if isMyApp {
                    Circle()
                        .stroke(.purple, lineWidth: 2)
                        .frame(width: 24, height: 24)
                }
            }
        case .unavailable:
            Image(systemName: "brain.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
    }

    func scoreColor(_ score: Int) -> Color {
        switch score {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .mint
        case 5: return .green
        default: return .gray
        }
    }

    /// Numeral color chosen to stay legible on the fill. In dark mode every fill
    /// is pastelized (lightened toward white), so dark digits read best across the
    /// board; in light mode only the already-light yellow/mint fills need them.
    func numeralColor(_ score: Int) -> Color {
        if colorScheme == .dark { return Color.black.opacity(0.8) }
        switch score {
        case 3, 4: return Color.black.opacity(0.8)
        default: return .white
        }
    }

}
