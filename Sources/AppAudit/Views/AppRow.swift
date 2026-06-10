import SwiftUI
import SwiftData

#if canImport(AppKit)
import AppKit
#endif

struct AppRow: View {
    let app: AppInfo
    @Environment(\.modelContext) private var modelContext
    @Environment(AppListViewModel.self) private var viewModel
    private let licenseKeyStore = LicenseKeyStore.shared
    @State private var editingLicenseKey = false
    @State private var draftLicenseKey = ""
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
                    if app.isMyApp {
                        Image(systemName: "hammer.fill")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    if app.isSubscribed {
                        Image(systemName: "creditcard.fill")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                    }
                    if existingLicenseKey != nil {
                        Image(systemName: "key.horizontal.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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

            ScoreBadgeView(state: app.aiState, isMyApp: app.isMyApp)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                Task { await viewModel.reanalyze(bundleID: app.bundleID) }
            } label: {
                Label("Re-analyze", systemImage: "arrow.clockwise")
            }
            .disabled(app.isAnalysisLocked)

            Divider()

            Button {
                toggleFavorite()
            } label: {
                if app.isFavorite {
                    Label("Remove from Favorites", systemImage: "star.slash")
                } else {
                    Label("Add to Favorites", systemImage: "star")
                }
            }

            Button {
                toggleMyApp()
            } label: {
                if app.isMyApp {
                    Label("Unmark as My App", systemImage: "hammer.slash")
                } else {
                    Label("Mark as My App", systemImage: "hammer.fill")
                }
            }

            Button {
                toggleSubscription()
            } label: {
                if app.isSubscribed {
                    Label("Unmark Subscription", systemImage: "creditcard.trianglebadge.exclamationmark")
                } else {
                    Label("Mark as Subscription", systemImage: "creditcard")
                }
            }

            Divider()

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

            if let licenseKey = existingLicenseKey {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(licenseKey, forType: .string)
                } label: {
                    Label("Copy Key", systemImage: "key.horizontal")
                }

                Button {
                    prepareLicenseKeyDraft()
                    editingLicenseKey = true
                } label: {
                    Label("Edit Key", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    removeLicenseKey()
                } label: {
                    Label("Remove Key", systemImage: "trash")
                }
            } else {
                Button {
                    prepareLicenseKeyDraft()
                    editingLicenseKey = true
                } label: {
                    Label("Add Key", systemImage: "key.badge.plus")
                }
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
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.bundleID, forType: .string)
            } label: {
                Label("Copy Bundle ID", systemImage: "doc.on.doc")
            }
        }
        .sheet(isPresented: $editingLicenseKey) {
            LicenseKeySheet(appName: app.name, draft: $draftLicenseKey) { saved in
                if saved {
                    saveLicenseKey()
                }
                editingLicenseKey = false
            }
        }
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

    private func toggleSubscription() {
        let bundleID = app.bundleID
        if let existing = fetchRecord(for: bundleID) {
            existing.hasSubscription.toggle()
            try? modelContext.save()
            viewModel.setSubscription(bundleID: bundleID, value: existing.hasSubscription)
        } else {
            let rec = makeStubRecord()
            rec.hasSubscription = true
            modelContext.insert(rec)
            try? modelContext.save()
            viewModel.setSubscription(bundleID: bundleID, value: true)
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

    private func prepareLicenseKeyDraft() {
        draftLicenseKey = existingLicenseKey ?? ""
    }

    private func saveLicenseKey() {
        let trimmed = draftLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = fetchRecord(for: app.bundleID) ?? {
            let record = makeStubRecord()
            modelContext.insert(record)
            return record
        }()

        licenseKeyStore.save(trimmed, bundleID: app.bundleID)
        record.licenseKey = nil
        record.hasLicenseKey = !trimmed.isEmpty
        try? modelContext.save()
    }

    private func removeLicenseKey() {
        licenseKeyStore.delete(bundleID: app.bundleID)
        if let record = fetchRecord(for: app.bundleID) {
            record.licenseKey = nil
            record.hasLicenseKey = false
            try? modelContext.save()
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
            return "sparkles"
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

private struct LicenseKeySheet: View {
    let appName: String
    @Binding var draft: String
    let onDone: (Bool) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("License key for \(appName)")
                .font(.headline)
            Text("Store the purchased key for this app so you can copy it later from the context menu.")
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
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { focused = true }
    }
}

struct ScoreBadgeView: View {
    let state: AppInfo.AIState
    var isMyApp: Bool = false

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
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(scoreColor(score), in: Circle())
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

}
