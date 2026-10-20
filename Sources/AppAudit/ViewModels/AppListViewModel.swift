import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

@MainActor
@Observable
final class AppListViewModel {

    var apps: [AppInfo] = []
    var scanState: ScanState = .idle
    var selectedAppID: String? = nil
    /// Set by the sidebar's "Add/Edit License…" — the detail view opens its
    /// License popover for this bundle ID, then clears the request.
    var licensePopoverRequestID: String? = nil
    var workflowProfile: WorkflowProfile = .current()
    var searchText = ""
    var sortOrder: SortOrder = .relevance
    var isRefreshingUpdates = false

    /// App-wide flag for presenting the License Vault sheet (set from the toolbar
    /// menu or the macOS menu bar).
    var showingVault = false
    /// The What's new sheet's lines while it is shown (once after an update, or from Help).
    var whatsNewLines: [WhatsNew.Line]? = nil

    /// Number of displayed, unlocked analyses that were generated with a model
    /// other than the one currently selected. Drives the "model changed" banner.
    var staleModelCount = 0

    /// The model the banner count was last computed against. Settings writes
    /// UserDefaults directly, so the view model compares on every defaults change.
    private var countedModelIdentifier: String? = nil

    /// Max number of apps analyzed in parallel. Kept low to limit peak memory and
    /// CPU while local AI runs in the background.
    private let enrichmentConcurrency = 2

    enum ReanalyzeScope {
        case allUnlocked
        case modelChangedUnlocked
    }

    var availableUpdateCount: Int {
        apps.filter(\.updateState.isUpdateAvailable).count
    }

    enum ScanState: Equatable {
        case idle
        case scanning
        case enriching(completed: Int, total: Int)
        case done
        case error(String)

    }

    enum SortOrder: String, CaseIterable {
        case relevance = "Relevance"
        case updates = "Updates"
        case lastUsed = "Last Used"
        case name = "Name"
    }

    /// Filter toggles applied on top of the current sort. (My Apps and Favorites
    /// used to be sort modes; they are now filters.)
    var filterMyApps = false
    var filterFavorites = false

    enum SidebarEmptyState: Equatable {
        case noApps
        case noResults
        case noUpdates
        case noMyApps
        case noFavorites
    }

    var filteredApps: [AppInfo] {
        var base = searchText.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        if filterMyApps {
            base = base.filter(\.isMyApp)
        }
        if filterFavorites {
            base = base.filter(\.isFavorite)
        }
        if sortOrder == .updates {
            base = base.filter { $0.updateState.belongsInUpdatesList }
        }
        return base.sorted { a, b in
            switch sortOrder {
            case .name:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .updates:
                return updateSortKey(a).localizedCaseInsensitiveCompare(updateSortKey(b)) == .orderedAscending
            case .relevance:
                return (a.aiState.score ?? 0) > (b.aiState.score ?? 0)
            case .lastUsed:
                return lastUsedIsOrderedBefore(a, b)
            }
        }
    }

    /// Most recently used first; apps Spotlight has never seen sort to the bottom,
    /// then alphabetically for stability.
    private func lastUsedIsOrderedBefore(_ a: AppInfo, _ b: AppInfo) -> Bool {
        switch (a.lastUsedDate, b.lastUsedDate) {
        case let (da?, db?):
            if da == db {
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return da > db
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var sidebarEmptyState: SidebarEmptyState? {
        guard filteredApps.isEmpty else { return nil }
        if apps.isEmpty { return .noApps }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .noResults }
        if sortOrder == .updates { return .noUpdates }
        if filterFavorites { return .noFavorites }
        if filterMyApps { return .noMyApps }
        return .noApps
    }

    private func updateSortKey(_ app: AppInfo) -> String {
        if case .updateAvailable(_, let source, _) = app.updateState {
            return "\(source.rawValue)-\(app.name)"
        }
        return app.name
    }

    func showAvailableUpdates() {
        searchText = ""
        sortOrder = .updates
        reconcileSelectionWithCurrentFilter(selectFirstIfNeeded: true)
    }

    func setSearchText(_ text: String) {
        searchText = text
        reconcileSelectionWithCurrentFilter(selectFirstIfNeeded: true)
    }

    func setSortOrder(_ order: SortOrder) {
        sortOrder = order
        reconcileSelectionWithCurrentFilter(selectFirstIfNeeded: true)
    }

    func setFilterMyApps(_ value: Bool) {
        filterMyApps = value
        reconcileSelectionWithCurrentFilter(selectFirstIfNeeded: true)
    }

    func setFilterFavorites(_ value: Bool) {
        filterFavorites = value
        reconcileSelectionWithCurrentFilter(selectFirstIfNeeded: true)
    }

    func clearFilters() {
        filterMyApps = false
        filterFavorites = false
        reconcileSelectionWithCurrentFilter(selectFirstIfNeeded: true)
    }

    func reconcileSelectionWithCurrentFilter(selectFirstIfNeeded: Bool = false) {
        let visibleApps = filteredApps

        if let selectedAppID,
           visibleApps.contains(where: { $0.id == selectedAppID }) {
            return
        }

        if selectedAppID != nil || selectFirstIfNeeded {
            selectedAppID = visibleApps.first?.id
        }
    }

    nonisolated static let checkUpdatesOnScanKey = "checkUpdatesOnScan"

    /// Whether each scan asks the Mac App Store, vendor update feeds and GitHub
    /// for updates and links. On unless turned off in Settings → General.
    nonisolated static func checksUpdatesOnScan(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: checkUpdatesOnScanKey) as? Bool ?? true
    }

    func refreshUpdateStatuses() async {
        guard !isRefreshingUpdates,
              scanState != .scanning,
              !apps.isEmpty else {
            return
        }

        isRefreshingUpdates = true
        defer { isRefreshingUpdates = false }

        let token = UUID()
        updateScanToken = token
        let appsToRefresh = apps.filter { isUpdateCandidate($0) }
        let visibleUpdateIDs = Set(apps.filter { $0.updateState.isUpdateAvailable }.map(\.id))

        for index in apps.indices where visibleUpdateIDs.contains(apps[index].id) {
            apps[index].updateState = .checking
        }

        await refreshUpdates(for: appsToRefresh, token: token)
        reconcileSelectionWithCurrentFilter()
    }

    private let scanner = AppScanner()
    private let ollama = OllamaService()
    private let cloudServices: [AnalysisProviderKind: any AnalysisService] = Dictionary(
        uniqueKeysWithValues: AnalysisProviderKind.allCases
            .filter { $0 != .ollama }
            .map { ($0, AnalysisServices.make($0)) }
    )

    /// The service for a provider; Ollama is held separately because its parser
    /// serves every provider's output.
    private func service(for kind: AnalysisProviderKind) -> any AnalysisService {
        kind == .ollama ? ollama : cloudServices[kind] ?? ollama
    }
    private let updateChecker = UpdateChecker()
    private let appLinkResolver = AppLinkResolver()
    private let linkEvidenceService = LinkEvidenceService()
    var cacheService: CacheService?
    private var updateScanToken = UUID()

    func runFullScan() async {
        guard scanState == .idle || scanState == .done else { return }
        apps = []
        staleModelCount = 0
        scanState = .scanning

        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let scannedApps = await scanner.scan(runningBundleIDs: runningIDs)
        let digest = WorkflowDigest.build(from: scannedApps, includeAppNames: AnalysisProviderKind.current().runsOnThisMac)
        UserDefaults.standard.set(digest, forKey: "lastProfileDigest")
        workflowProfile = .current(digest: digest)
        apps = scannedApps
        let updateToken = UUID()
        updateScanToken = updateToken

        // Off in Settings → General: a scan stays on this Mac. The refresh
        // button in the sidebar still checks when clicked.
        if Self.checksUpdatesOnScan() {
            for index in apps.indices where !apps[index].version.isEmpty {
                apps[index].updateState = .checking
            }

            Task {
                await self.refreshUpdates(for: scannedApps, token: updateToken)
            }

            Task {
                await self.refreshAppLinks(for: scannedApps, token: updateToken)
            }
        }

        let provider = AnalysisProviderKind.current()
        await selectInstalledOllamaModelIfNeeded(provider: provider)
        let modelIdentifier = provider.modelIdentifier

        // Check cache for each app
        var toEnrich: [AppInfo] = []
        if let cache = cacheService {
            for i in apps.indices {
                if let record = cache.load(bundleID: apps[i].bundleID) {
                    apps[i].isMyApp = record.isMyApp
                    apps[i].isFavorite = record.isFavorite
                    apps[i].isSubscribed = record.hasSubscription
                    apps[i].isPaidApp = record.isPaidApp
                    apps[i].isAnalysisLocked = record.isAnalysisLocked
                    apps[i].isFreeApp = record.isFreeApp
                    apps[i].licenseTypeRaw = record.licenseType
                    apps[i].hasLicenseKey = record.hasLicenseKey
                    if record.hasLicenseKey, record.iconPNG == nil {
                        record.iconPNG = apps[i].icon?.pngData()
                    }
                    let currentAppURL = record.appURL
                    // Builds before 1.13 cached unreadable model output as an
                    // analysis; those records are re-analyzed, not shown.
                    let isUnparsedFallback = record.relevanceReason == Self.legacyUnparsedReason
                        && !record.isAnalysisLocked
                    if !record.explanation.isEmpty, !isUnparsedFallback,
                       (record.isAnalysisLocked || !cache.isStale(record, currentModel: modelIdentifier, currentAppURL: currentAppURL)) {
                        apps[i].aiState = .loaded(
                            explanation: record.explanation,
                            score: record.relevanceScore,
                            reason: record.relevanceReason,
                            bestUse: record.bestUse ?? ""
                        )
                    } else if !record.isAnalysisLocked {
                        toEnrich.append(apps[i])
                    }
                } else {
                    toEnrich.append(apps[i])
                }
            }
        } else {
            toEnrich = apps
        }
        cacheService?.persist()
        recomputeStaleModelCount(force: true)

        // Two installed copies share a bundle ID and one record: analyze once.
        var seenBundleIDs = Set<String>()
        toEnrich = toEnrich.filter { seenBundleIDs.insert($0.bundleID).inserted }

        scanState = .enriching(completed: apps.count - toEnrich.count, total: apps.count)

        await enrichConcurrently(apps: toEnrich, profile: workflowProfile, provider: provider, modelIdentifier: modelIdentifier)

        scanState = .done
    }

    /// A new Mac rarely has the default model. Before analyzing with Ollama,
    /// switch to an installed model when the chosen one isn't there, the same
    /// way Settings → Models does, so a first scan doesn't fail on every app.
    /// Leaves the choice alone when Ollama can't be reached.
    private func selectInstalledOllamaModelIfNeeded(provider: AnalysisProviderKind) async {
        guard provider == .ollama,
              case .models(let models) = await ollama.fetchModels(),
              let replacement = provider.modelToSelect(from: models) else { return }
        UserDefaults.standard.set(replacement, forKey: provider.modelDefaultsKey)
    }

    private func enrichConcurrently(
        apps toEnrich: [AppInfo],
        profile: WorkflowProfile,
        provider: AnalysisProviderKind,
        modelIdentifier: String
    ) async {
        let concurrencyLimit = enrichmentConcurrency
        var completed = self.apps.count - toEnrich.count

        await withTaskGroup(of: (String, AppInfo.AIState, String?).self) { group in
            var pendingCount = 0
            var iterator = toEnrich.makeIterator()

            // Seed initial batch
            while pendingCount < concurrencyLimit, let app = iterator.next() {
                let capturedApp = app
                let capturedProfile = profile
                let capturedProvider = provider
                let capturedRecord = self.cacheService?.load(bundleID: app.bundleID)
                let capturedAppURL = capturedRecord?.appURL
                let capturedNotes = capturedRecord?.notes
                let capturedDocs = capturedRecord?.docsEvidence
                group.addTask {
                    let result = await self.enrichSingle(app: capturedApp, profile: capturedProfile, provider: capturedProvider, appURL: capturedAppURL, userNotes: capturedNotes, docsEvidence: capturedDocs)
                    return (result.0, result.1, capturedAppURL)
                }
                pendingCount += 1
            }

            // Process results and add more as slots free up
            for await result in group {
                let (bundleID, state, analysisAppURL) = result
                if let idx = self.apps.firstIndex(where: { $0.bundleID == bundleID }) {
                    let isLocked = self.apps[idx].isAnalysisLocked ||
                        self.cacheService?.load(bundleID: bundleID)?.isAnalysisLocked == true

                    if !isLocked {
                        self.update(bundleID: bundleID) { $0.aiState = state }

                        if case .loaded(let explanation, let score, let reason, let bestUse) = state,
                           let cache = self.cacheService,
                           cache.load(bundleID: bundleID)?.isAnalysisLocked != true {
                            cache.save(
                                bundleID: bundleID,
                                appName: self.apps[idx].name,
                                explanation: explanation,
                                score: score,
                                reason: reason,
                                bestUse: bestUse,
                                ollamaModel: modelIdentifier,
                                analysisAppURL: analysisAppURL
                            )
                        }
                    }
                }

                completed += 1
                self.scanState = .enriching(completed: completed, total: self.apps.count)

                if let next = iterator.next() {
                    let capturedNext = next
                    let capturedProfile = profile
                    let capturedProvider = provider
                    let capturedRecord = self.cacheService?.load(bundleID: next.bundleID)
                    let capturedAppURL = capturedRecord?.appURL
                    let capturedNotes = capturedRecord?.notes
                    let capturedDocs = capturedRecord?.docsEvidence
                    group.addTask {
                        let result = await self.enrichSingle(app: capturedNext, profile: capturedProfile, provider: capturedProvider, appURL: capturedAppURL, userNotes: capturedNotes, docsEvidence: capturedDocs)
                        return (result.0, result.1, capturedAppURL)
                    }
                }
            }
        }
    }

    nonisolated private func enrichSingle(
        app: AppInfo,
        profile: WorkflowProfile,
        provider: AnalysisProviderKind,
        appURL: String? = nil,
        userNotes: String? = nil,
        docsEvidence: String? = nil
    ) async -> (String, AppInfo.AIState) {
        let linkEvidence = await linkEvidenceService.evidence(for: appURL)
        let result = await service(for: provider).analyze(app: app, profile: profile, appURL: appURL, linkEvidence: linkEvidence, userNotes: userNotes, docsEvidence: docsEvidence)

        switch result {
        case .unavailable(let msg):
            return (app.bundleID, .unavailable(msg))
        case .success(let response):
            if let parsed = await ollama.parseAnalysis(from: response) {
                return (app.bundleID, .loaded(
                    explanation: parsed.explanation,
                    score: parsed.score,
                    reason: parsed.reason,
                    bestUse: parsed.bestUse
                ))
            } else {
                // The model ignored the format, or spent its whole answer
                // thinking. Raw output is not an analysis: show it as a failure
                // the user can retry, and keep it out of the cache.
                return (app.bundleID, .unavailable(Self.unparsedMessage))
            }
        }
    }

    nonisolated static let unparsedMessage = "The model's answer could not be read. Try again, or pick another model in Settings."
    /// The reason older builds stored alongside unparsed model output.
    nonisolated static let legacyUnparsedReason = "Could not parse analysis"

    /// Mutate the in-memory app(s) with this bundle ID; a no-op if none is in
    /// the list. Two installed copies share one record, so record-backed state
    /// (analysis, marks, license) is mirrored onto every copy.
    func update(bundleID: String, _ body: (inout AppInfo) -> Void) {
        for idx in apps.indices where apps[idx].bundleID == bundleID {
            body(&apps[idx])
        }
    }

    func setMyApp(bundleID: String, value: Bool) { update(bundleID: bundleID) { $0.isMyApp = value } }
    func setFavorite(bundleID: String, value: Bool) { update(bundleID: bundleID) { $0.isFavorite = value } }
    func setSubscription(bundleID: String, value: Bool) { update(bundleID: bundleID) { $0.isSubscribed = value } }
    func setPaidApp(bundleID: String, value: Bool) { update(bundleID: bundleID) { $0.isPaidApp = value } }
    func setFreeApp(bundleID: String, value: Bool) { update(bundleID: bundleID) { $0.isFreeApp = value } }
    func setLicenseType(bundleID: String, rawValue: String?) { update(bundleID: bundleID) { $0.licenseTypeRaw = rawValue } }
    func setHasLicenseKey(bundleID: String, value: Bool) { update(bundleID: bundleID) { $0.hasLicenseKey = value } }

    /// Drops one uninstalled copy from the in-memory list, by its path-based
    /// id: another copy with the same bundle ID stays. Its AppRecord is
    /// deliberately kept — license keys, notes, and marks survive, and the
    /// License Vault lists it under "No longer installed".
    func removeApp(id: String) {
        apps.removeAll { $0.id == id }
        reconcileSelectionWithCurrentFilter()
    }

    /// Reconcile each record's `hasLicenseKey` flag with the Keychain. Runs at
    /// launch so the License Vault is accurate without reading secrets at render
    /// time. For the app that owns the Keychain items this does not prompt.
    func syncLicenseFlags() {
        guard let cache = cacheService else { return }
        let store = LicenseKeyStore.shared
        var changed = false
        for record in cache.allRecords() {
            let has = store.hasKey(bundleID: record.bundleID)
            if record.hasLicenseKey != has {
                record.hasLicenseKey = has
                changed = true
            }
            setHasLicenseKey(bundleID: record.bundleID, value: has)
        }
        if changed { cache.persist() }
    }

    /// One-time: users upgraded from builds where the personal default profile was
    /// pre-stored. If the stored profile is exactly that old default, clear it so
    /// the new automatic digest takes over (a deliberate custom profile differs
    /// from the default text and is preserved).
    func migrateDefaultProfileToAutomatic() {
        let defaults = UserDefaults.standard
        let stored = (defaults.string(forKey: WorkflowProfile.storageKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stored == WorkflowProfile.defaultProfileText.trimmingCharacters(in: .whitespacesAndNewlines) {
            defaults.removeObject(forKey: WorkflowProfile.storageKey)
        }
    }

    /// One-time: the Style note moved from an Apple-Intelligence-only key to a
    /// global `analysisStyleNotes` key. Carry any existing value across so it
    /// keeps working for every engine. No-op once the new key exists.
    func migrateStyleNotesKey() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "analysisStyleNotes") == nil else { return }
        let old = (defaults.string(forKey: "appleIntelligenceStyleNotes") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !old.isEmpty {
            defaults.set(old, forKey: "analysisStyleNotes")
        }
    }

    /// Sweep: move any lingering plaintext license keys out of the SwiftData store
    /// and into the Keychain, then null the legacy field. Checks for existing keys
    /// by attributes only, so it does not prompt. The done flag is set only once no
    /// plaintext key is left: a key the Keychain refused is retried next launch.
    func migrateLegacyLicenseKeys(store: LicenseKeyStore = .shared, defaults: UserDefaults = .standard) {
        let flagKey = "didMigrateLegacyLicenseKeys"
        guard !defaults.bool(forKey: flagKey) else { return }
        guard let cache = cacheService else { return }

        var changed = false
        var leftBehind = 0
        for record in cache.allRecords() {
            guard let legacy = record.licenseKey, !legacy.isEmpty else { continue }
            let present = store.migrateLegacyKey(legacy, bundleID: record.bundleID)
            // Only drop the plaintext once the Keychain verifiably holds the key —
            // a denied prompt here must not be the moment the key is lost.
            guard present else {
                leftBehind += 1
                continue
            }
            record.licenseKey = nil
            record.hasLicenseKey = true
            changed = true
        }
        if changed { cache.persist() }
        if leftBehind == 0 { defaults.set(true, forKey: flagKey) }
    }

    /// Runs the Save panel and writes the audit CSV. Callable from the menu bar.
    func exportCSVToFile() {
        guard !apps.isEmpty else { return }
        let csv = exportCSV()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Sift-\(formatter.string(from: Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.title = "Export Audit to CSV"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "The CSV could not be saved"
            alert.informativeText = "\(url.path): \(error.localizedDescription)"
            alert.runModal()
        }
    }

    /// Full-audit CSV of every scanned app. Never includes license keys.
    func exportCSV() -> String {
        let header = [
            "Name", "Bundle ID", "Version", "Category", "Score", "Recommendation",
            "Explanation", "Update Status", "My App", "Favorite",
            "Subscription", "Sub Price", "Sub Cycle", "Sub Renewal",
            "Source", "Paid", "Notes"
        ]
        let sorted = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let rows: [[String]] = sorted.map { app in
            let record = cacheService?.load(bundleID: app.bundleID)
            var score = ""
            var bestUse = ""
            var explanation = ""
            if case .loaded(let e, let s, _, let b) = app.aiState {
                explanation = e
                score = String(s)
                bestUse = b
            }
            return [
                app.name,
                app.bundleID,
                app.version,
                AppCategory.humanName(for: app.category) ?? "",
                score,
                bestUse,
                explanation,
                updateStatusText(app.updateState),
                app.isMyApp ? "yes" : "no",
                app.isFavorite ? "yes" : "no",
                app.isSubscribed ? "yes" : "no",
                record?.subscriptionPrice.map { String(format: "%.2f", $0) } ?? "",
                record?.subscriptionCycle ?? "",
                record?.subscriptionRenewalDate.map { SubscriptionMath.isoDate($0) } ?? "",
                app.installSourceLabel,
                Self.paidColumn(isPaidApp: record?.isPaidApp == true,
                                hasLicenseKey: record?.hasLicenseKey == true,
                                licenseType: record?.licenseType),
                record?.notes ?? ""
            ]
        }
        return CSVExporter.make(header: header, rows: rows)
    }

    /// Any trace of a purchase counts: the Paid mark, a saved key, or a
    /// license type. (A Free mark clears Paid, so it never reads "yes".)
    nonisolated static func paidColumn(isPaidApp: Bool, hasLicenseKey: Bool, licenseType: String?) -> String {
        (isPaidApp || hasLicenseKey || licenseType != nil) ? "yes" : ""
    }

    private func updateStatusText(_ state: AppInfo.UpdateState) -> String {
        switch state {
        case .updateAvailable(let latestVersion, let source, _):
            return "Update available: \(latestVersion) (\(source.rawValue))"
        case .upToDate(let source):
            return "Up to date (\(source.rawValue))"
        case .checking:
            return "Checking"
        case .unknown, .unavailable:
            return "Unknown"
        }
    }

    func setAnalysisLocked(bundleID: String, value: Bool) { update(bundleID: bundleID) { $0.isAnalysisLocked = value } }

    func acknowledgeUpdate(bundleID: String, updateState: AppInfo.UpdateState) {
        guard let cache = cacheService else { return }
        let acknowledgedVersion: String?
        let nextState: AppInfo.UpdateState

        switch updateState {
        case .updateAvailable(let latestVersion, let source, _):
            acknowledgedVersion = latestVersion
            nextState = .upToDate(source: source)
        default:
            acknowledgedVersion = nil
            nextState = updateState
        }

        let record = cache.ensureRecord(bundleID: bundleID,
                                        appName: apps.first(where: { $0.bundleID == bundleID })?.name ?? bundleID)
        record.acknowledgedUpdateVersion = acknowledgedVersion
        cache.persist()

        // Copies can run different versions; only those showing this same
        // update are marked done.
        for idx in apps.indices where apps[idx].bundleID == bundleID && apps[idx].updateState == updateState {
            apps[idx].updateState = nextState
        }

        reconcileSelectionWithCurrentFilter()
    }

    private func ensureCachedRecord(bundleID: String, appName: String) -> AppRecord? {
        cacheService?.ensureRecord(bundleID: bundleID, appName: appName)
    }

    func reanalyze(bundleID: String, appURL overrideAppURL: String? = nil) async {
        await selectInstalledOllamaModelIfNeeded(provider: AnalysisProviderKind.current())
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        guard cacheService?.load(bundleID: bundleID)?.isAnalysisLocked != true,
              !apps[idx].isAnalysisLocked else {
            return
        }
        let cachedRecord = cacheService?.load(bundleID: bundleID)
        let appURL = overrideAppURL ?? cachedRecord?.appURL
        let userNotes = cachedRecord?.notes
        let docsEvidence = cachedRecord?.docsEvidence
        workflowProfile = .current(digest: WorkflowDigest.build(from: apps, includeAppNames: AnalysisProviderKind.current().runsOnThisMac))
        update(bundleID: bundleID) { $0.aiState = .loading }
        let provider = AnalysisProviderKind.current()
        let result = await enrichSingle(app: apps[idx], profile: workflowProfile, provider: provider, appURL: appURL, userNotes: userNotes, docsEvidence: docsEvidence)
        // `apps` may have been rescanned or shrunk (⌘R, Uninstall) while we waited —
        // the old index could now point at another app, or past the end.
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        guard cacheService?.load(bundleID: bundleID)?.isAnalysisLocked != true,
              !apps[idx].isAnalysisLocked else {
            return
        }
        update(bundleID: bundleID) { $0.aiState = result.1 }

        let modelIdentifier = provider.modelIdentifier
        if case .loaded(let explanation, let score, let reason, let bestUse) = result.1,
           let cache = cacheService {
            cache.save(
                bundleID: bundleID,
                appName: apps[idx].name,
                explanation: explanation,
                score: score,
                reason: reason,
                bestUse: bestUse,
                ollamaModel: modelIdentifier,
                analysisAppURL: appURL
            )
            // Re-sync isMyApp (save() preserves it; read back to stay in sync)
            if let record = cache.load(bundleID: bundleID) {
                update(bundleID: bundleID) {
                    $0.isMyApp = record.isMyApp
                    $0.isFavorite = record.isFavorite
                    $0.isSubscribed = record.hasSubscription
                    $0.isPaidApp = record.isPaidApp
                    $0.isAnalysisLocked = record.isAnalysisLocked
                    $0.isFreeApp = record.isFreeApp
                    $0.licenseTypeRaw = record.licenseType
                    $0.hasLicenseKey = record.hasLicenseKey
                }
            }
        }
    }

    func dismissModelChangeBanner() {
        staleModelCount = 0
    }

    /// Counts displayed, unlocked analyses made with a model other than the
    /// one now selected. Called after a scan, and whenever UserDefaults
    /// changes: without `force` it only recounts when the provider or model
    /// actually changed, so a dismissed banner stays dismissed until then.
    func recomputeStaleModelCount(force: Bool = false) {
        let modelIdentifier = AnalysisProviderKind.current().modelIdentifier
        guard force || modelIdentifier != countedModelIdentifier else { return }
        countedModelIdentifier = modelIdentifier
        guard let cache = cacheService else { staleModelCount = 0; return }
        var counted = Set<String>()
        for app in apps where app.aiState.score != nil && !counted.contains(app.bundleID) {
            if let record = cache.load(bundleID: app.bundleID),
               cache.wasAnalyzedWithDifferentModel(record, currentModel: modelIdentifier) {
                counted.insert(app.bundleID)
            }
        }
        staleModelCount = counted.count
    }

    /// Re-runs analysis for many apps at once. Locked analyses are always skipped.
    /// `.modelChangedUnlocked` targets only apps whose cached analysis came from a
    /// different model; `.allUnlocked` targets every unlocked app.
    func reanalyzeAll(scope: ReanalyzeScope) async {
        guard scanState == .done || scanState == .idle else { return }

        workflowProfile = .current(digest: WorkflowDigest.build(from: apps, includeAppNames: AnalysisProviderKind.current().runsOnThisMac))
        let provider = AnalysisProviderKind.current()
        await selectInstalledOllamaModelIfNeeded(provider: provider)
        let modelIdentifier = provider.modelIdentifier

        var targets: [AppInfo] = []
        var seenBundleIDs = Set<String>()
        for app in apps where seenBundleIDs.insert(app.bundleID).inserted {
            let record = cacheService?.load(bundleID: app.bundleID)
            let locked = app.isAnalysisLocked || record?.isAnalysisLocked == true
            if locked { continue }
            if scope == .modelChangedUnlocked {
                guard let record,
                      !record.explanation.isEmpty,
                      record.ollamaModel != modelIdentifier else { continue }
            }
            targets.append(app)
        }

        guard !targets.isEmpty else {
            staleModelCount = 0
            return
        }

        let targetIDs = Set(targets.map(\.bundleID))
        for idx in apps.indices where targetIDs.contains(apps[idx].bundleID) {
            apps[idx].aiState = .loading
        }

        scanState = .enriching(completed: apps.count - targets.count, total: apps.count)
        await enrichConcurrently(apps: targets, profile: workflowProfile, provider: provider, modelIdentifier: modelIdentifier)
        scanState = .done
        staleModelCount = 0
    }

    func reanalyzeAfterLinkChange(bundleID: String, appURL: String? = nil) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }),
              !apps[idx].isAnalysisLocked,
              cacheService?.load(bundleID: bundleID)?.isAnalysisLocked != true else {
            return
        }

        Task {
            await reanalyze(bundleID: bundleID, appURL: appURL)
        }
    }

    /// A saved GitHub repo link is an update source, so changing the link changes
    /// the answer. Rechecks this one app; the link is passed in because the
    /// detail view saves it a moment before the cache can read it back.
    func recheckUpdateAfterLinkChange(bundleID: String, appURL: String?) {
        let acknowledgedVersion = cacheService?.load(bundleID: bundleID)?.acknowledgedUpdateVersion
        let checker = updateChecker
        let token = updateScanToken
        // Each installed copy has its own version, so each gets its own answer.
        for app in apps where app.bundleID == bundleID && !app.version.isEmpty {
            let appID = app.id
            Task {
                let state = await checker.check(app: app, acknowledgedVersion: acknowledgedVersion, appURL: appURL)
                // A full refresh started meanwhile owns the answer.
                guard token == updateScanToken,
                      let idx = apps.firstIndex(where: { $0.id == appID }) else { return }
                apps[idx].updateState = state
            }
        }
    }

    /// Re-runs analysis after the user attaches, refreshes, or removes an app's
    /// local docs folder, so the new evidence feeds the prompt. Locked analyses
    /// are never re-run — the evidence waits for a manual run after unlocking.
    func reanalyzeAfterDocsChange(bundleID: String) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }),
              !apps[idx].isAnalysisLocked,
              cacheService?.load(bundleID: bundleID)?.isAnalysisLocked != true else {
            return
        }
        Task {
            await reanalyze(bundleID: bundleID)
        }
    }

    /// Called when a notes editing session ends (the editor collapsed or the
    /// selection changed). Re-runs analysis when the note text meaningfully
    /// changed since the session began, so the new note feeds the prompt.
    /// Locked analyses are never re-run — the note waits for a manual run.
    func reanalyzeAfterNotesChange(bundleID: String, previousNotes: String?) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }),
              !apps[idx].isAnalysisLocked,
              let record = cacheService?.load(bundleID: bundleID),
              !record.isAnalysisLocked,
              NotesChange.changed(previous: previousNotes, current: record.notes) else {
            return
        }

        Task {
            await reanalyze(bundleID: bundleID)
        }
    }

    /// Asks the current model which of the user's OTHER installed apps overlap
    /// in function with `bundleID`. The model only ever sees a numbered list of
    /// installed apps and can only pick from it, so the result is grounded —
    /// no invented apps or dead links.
    func findSimilarApps(to bundleID: String) async -> [SimilarApp] {
        guard let target = apps.first(where: { $0.bundleID == bundleID }) else { return [] }

        var candidates: [SimilarAppsPrompt.Candidate] = []
        var indexToApp: [Int: (bundleID: String, name: String)] = [:]
        var i = 1
        for app in apps where app.bundleID != bundleID {
            candidates.append(.init(
                index: i,
                name: app.name,
                category: AppCategory.humanName(for: app.category) ?? "",
                explanation: Self.explanationText(app)
            ))
            indexToApp[i] = (app.bundleID, app.name)
            i += 1
        }
        guard !candidates.isEmpty else { return [] }

        let prompt = SimilarAppsPrompt.build(
            targetName: target.name,
            targetCategory: AppCategory.humanName(for: target.category) ?? "",
            targetExplanation: Self.explanationText(target),
            candidates: candidates
        )

        let text = await service(for: AnalysisProviderKind.current()).complete(prompt: prompt).successText
        guard !text.isEmpty else { return [] }

        return SimilarAppsPrompt.parse(text, validIndices: Set(indexToApp.keys))
            .prefix(4)
            .compactMap { pick in
                guard let app = indexToApp[pick.index] else { return nil }
                return SimilarApp(bundleID: app.bundleID, name: app.name, reason: pick.reason)
            }
    }

    private static func explanationText(_ app: AppInfo) -> String {
        if case .loaded(let explanation, _, _, _) = app.aiState { return explanation }
        return ""
    }

    /// An app is worth an update check when it has a channel of its own or the
    /// user saved a GitHub repo link for it — that repo's releases then answer.
    private func isUpdateCandidate(_ app: AppInfo) -> Bool {
        guard !app.version.isEmpty else { return false }
        if app.canCheckForUpdates { return true }
        let appURL = cacheService?.load(bundleID: app.bundleID)?.appURL
        return UpdateChecker.gitHubLatestReleaseURL(forAppURL: appURL) != nil
    }

    private func refreshUpdates(for scannedApps: [AppInfo], token: UUID) async {
        await updateChecker.resetHomebrewCache()

        // A few apps at a time: dead vendor feeds (abandoned apps are exactly what an
        // audit tool sees) would otherwise stack their timeouts end to end.
        let candidates = scannedApps.filter { isUpdateCandidate($0) }
        let batchSize = 4
        var start = 0
        while start < candidates.count {
            let batch = Array(candidates[start..<min(start + batchSize, candidates.count)])
            start += batchSize
            // Two installed copies of one app share a bundle ID (and one record),
            // so the keys are not unique — `uniqueKeysWithValues` traps on that.
            let acknowledged = Dictionary(batch.map {
                ($0.bundleID, cacheService?.load(bundleID: $0.bundleID)?.acknowledgedUpdateVersion)
            }, uniquingKeysWith: { first, _ in first })
            let appURLs = Dictionary(batch.map {
                ($0.bundleID, cacheService?.load(bundleID: $0.bundleID)?.appURL)
            }, uniquingKeysWith: { first, _ in first })
            let checker = updateChecker
            let results = await withTaskGroup(of: (String, AppInfo.UpdateState).self) { group in
                for app in batch {
                    let acknowledgedVersion = acknowledged[app.bundleID] ?? nil
                    let appURL = appURLs[app.bundleID] ?? nil
                    group.addTask { (app.id, await checker.check(app: app, acknowledgedVersion: acknowledgedVersion, appURL: appURL)) }
                }
                var collected: [(String, AppInfo.UpdateState)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            guard token == updateScanToken else { return }
            // Keyed by the per-copy id: two copies of one app can be at
            // different versions, and each needs its own answer.
            for (appID, state) in results {
                if let idx = apps.firstIndex(where: { $0.id == appID }) {
                    apps[idx].updateState = state
                }
            }
        }

        guard token == updateScanToken else { return }
        for idx in apps.indices where apps[idx].updateState == .checking {
            apps[idx].updateState = .unavailable
        }
        reconcileSelectionWithCurrentFilter()
    }

    private func refreshAppLinks(for scannedApps: [AppInfo], token: UUID) async {
        for app in scannedApps where app.isAppStoreInstall || app.sparkleFeedURL != nil {
            guard token == updateScanToken else { return }
            if let existingURL = cacheService?.load(bundleID: app.bundleID)?.appURL,
               !existingURL.isEmpty {
                continue
            }

            guard let resolvedLink = await appLinkResolver.resolve(app: app),
                  token == updateScanToken,
                  let record = ensureCachedRecord(bundleID: app.bundleID, appName: app.name),
                  (record.appURL ?? "").isEmpty else {
                continue
            }

            record.suggestedAppURL = resolvedLink.url
            cacheService?.persist()
        }
    }
}

/// A grounded "similar app" pick — always one of the user's installed apps.
struct SimilarApp: Identifiable, Sendable {
    let bundleID: String
    let name: String
    let reason: String
    var id: String { bundleID }
}

/// Decides whether a note edit is worth an automatic re-analysis.
/// nil, empty, and whitespace-only text are all treated as "no note".
nonisolated enum NotesChange {
    static func changed(previous: String?, current: String?) -> Bool {
        func normalized(_ text: String?) -> String {
            (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalized(previous) != normalized(current)
    }
}
