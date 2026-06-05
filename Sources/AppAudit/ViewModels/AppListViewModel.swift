import SwiftUI
import SwiftData

@MainActor
@Observable
final class AppListViewModel {

    var apps: [AppInfo] = []
    var scanState: ScanState = .idle
    var selectedAppID: String? = nil
    var workflowProfile: WorkflowProfile = .current()
    var searchText = ""
    var sortOrder: SortOrder = .relevance
    var isRefreshingUpdates = false

    var availableUpdateCount: Int {
        apps.filter(\.updateState.isUpdateAvailable).count
    }

    enum ScanState: Equatable {
        case idle
        case scanning
        case enriching(completed: Int, total: Int)
        case done
        case error(String)

        static func == (lhs: ScanState, rhs: ScanState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.scanning, .scanning), (.done, .done): return true
            case let (.enriching(a, b), .enriching(c, d)): return a == c && b == d
            case let (.error(a), .error(b)): return a == b
            default: return false
            }
        }
    }

    enum SortOrder: String, CaseIterable {
        case relevance = "Relevance"
        case updates = "Updates"
        case lastUsed = "Last Used"
        case myApps = "My Apps"
        case name = "Name"
        case favorites = "Favorites"
    }

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
        switch sortOrder {
        case .updates:
            base = base.filter { $0.updateState.belongsInUpdatesList }
        case .myApps:
            base = base.filter { $0.isMyApp }
        case .favorites:
            base = base.filter { $0.isFavorite }
        default:
            break
        }
        return base.sorted { a, b in
            switch sortOrder {
            case .name, .myApps, .favorites:
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

        switch sortOrder {
        case .updates:
            return .noUpdates
        case .myApps:
            return .noMyApps
        case .favorites:
            return .noFavorites
        case .relevance, .name, .lastUsed:
            return .noApps
        }
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
        let appsToRefresh = apps.filter { !$0.version.isEmpty && $0.canCheckForUpdates }
        let visibleUpdateIDs = Set(apps.filter { $0.updateState.isUpdateAvailable }.map(\.id))

        for index in apps.indices where visibleUpdateIDs.contains(apps[index].id) {
            apps[index].updateState = .checking
        }

        await refreshUpdates(for: appsToRefresh, token: token)
        reconcileSelectionWithCurrentFilter()
    }

    private let scanner = AppScanner()
    private let ollama = OllamaService()
    private let appleIntelligence = AppleIntelligenceService()
    private let updateChecker = UpdateChecker()
    private let appLinkResolver = AppLinkResolver()
    var cacheService: CacheService?
    private var updateScanToken = UUID()

    func runFullScan() async {
        guard scanState == .idle || scanState == .done else { return }
        apps = []
        scanState = .scanning

        let scannedApps = await scanner.scan()
        workflowProfile = .current()
        apps = scannedApps
        let updateToken = UUID()
        updateScanToken = updateToken

        for index in apps.indices where !apps[index].version.isEmpty {
            apps[index].updateState = .checking
        }

        Task {
            await self.refreshUpdates(for: scannedApps, token: updateToken)
        }

        Task {
            await self.refreshAppLinks(for: scannedApps, token: updateToken)
        }

        let provider = AnalysisProviderKind.current()
        let modelIdentifier = provider.modelIdentifier

        // Check cache for each app
        var toEnrich: [AppInfo] = []
        if let cache = cacheService {
            for i in apps.indices {
                if let record = cache.load(bundleID: apps[i].bundleID) {
                    apps[i].isMyApp = record.isMyApp
                    apps[i].isFavorite = record.isFavorite
                    apps[i].isSubscribed = record.hasSubscription
                    apps[i].isAnalysisLocked = record.isAnalysisLocked
                    let currentAppURL = record.appURL
                    if !record.explanation.isEmpty,
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

        scanState = .enriching(completed: apps.count - toEnrich.count, total: apps.count)

        await enrichConcurrently(apps: toEnrich, profile: workflowProfile, provider: provider, modelIdentifier: modelIdentifier)

        scanState = .done
    }

    private func enrichConcurrently(
        apps toEnrich: [AppInfo],
        profile: WorkflowProfile,
        provider: AnalysisProviderKind,
        modelIdentifier: String
    ) async {
        let concurrencyLimit = 4
        var completed = self.apps.count - toEnrich.count

        await withTaskGroup(of: (String, AppInfo.AIState, String?).self) { group in
            var pendingCount = 0
            var iterator = toEnrich.makeIterator()

            // Seed initial batch
            while pendingCount < concurrencyLimit, let app = iterator.next() {
                let capturedApp = app
                let capturedProfile = profile
                let capturedProvider = provider
                let capturedAppURL = self.cacheService?.load(bundleID: app.bundleID)?.appURL
                group.addTask {
                    let result = await self.enrichSingle(app: capturedApp, profile: capturedProfile, provider: capturedProvider, appURL: capturedAppURL)
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
                        self.apps[idx].aiState = state

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
                    let capturedAppURL = self.cacheService?.load(bundleID: next.bundleID)?.appURL
                    group.addTask {
                        let result = await self.enrichSingle(app: capturedNext, profile: capturedProfile, provider: capturedProvider, appURL: capturedAppURL)
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
        appURL: String? = nil
    ) async -> (String, AppInfo.AIState) {
        let result: OllamaService.OllamaResult
        switch provider {
        case .ollama:
            result = await ollama.analyze(app: app, profile: profile, appURL: appURL)
        case .appleIntelligence:
            result = await appleIntelligence.analyze(app: app, profile: profile, appURL: appURL)
        }

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
                // Fallback: model didn't follow the format — store raw response as explanation
                return (app.bundleID, .loaded(explanation: response, score: 3, reason: "Could not parse analysis", bestUse: ""))
            }
        }
    }

    func setMyApp(bundleID: String, value: Bool) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        apps[idx].isMyApp = value
    }

    func setFavorite(bundleID: String, value: Bool) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        apps[idx].isFavorite = value
    }

    func setSubscription(bundleID: String, value: Bool) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        apps[idx].isSubscribed = value
    }

    func setAnalysisLocked(bundleID: String, value: Bool) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        apps[idx].isAnalysisLocked = value
    }

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

        let record = cache.load(bundleID: bundleID) ?? {
            let record = AppRecord(
                bundleID: bundleID,
                appName: apps.first(where: { $0.bundleID == bundleID })?.name ?? bundleID,
                explanation: "",
                relevanceScore: 0,
                relevanceReason: "",
                bestUse: "",
                ollamaModel: ""
            )
            cache.insert(record)
            return record
        }()
        record.acknowledgedUpdateVersion = acknowledgedVersion
        cache.persist()

        if let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) {
            apps[idx].updateState = nextState
        }

        reconcileSelectionWithCurrentFilter()
    }

    private func ensureCachedRecord(bundleID: String, appName: String) -> AppRecord? {
        guard let cache = cacheService else { return nil }
        if let record = cache.load(bundleID: bundleID) {
            return record
        }

        let record = AppRecord(
            bundleID: bundleID,
            appName: appName,
            explanation: "",
            relevanceScore: 0,
            relevanceReason: "",
            bestUse: "",
            ollamaModel: ""
        )
        cache.insert(record)
        return record
    }

    func reanalyze(bundleID: String, appURL overrideAppURL: String? = nil) async {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        guard cacheService?.load(bundleID: bundleID)?.isAnalysisLocked != true,
              !apps[idx].isAnalysisLocked else {
            return
        }
        let appURL = overrideAppURL ?? cacheService?.load(bundleID: bundleID)?.appURL
        workflowProfile = .current()
        apps[idx].aiState = .loading
        let provider = AnalysisProviderKind.current()
        let result = await enrichSingle(app: apps[idx], profile: workflowProfile, provider: provider, appURL: appURL)
        guard cacheService?.load(bundleID: bundleID)?.isAnalysisLocked != true,
              !apps[idx].isAnalysisLocked else {
            return
        }
        apps[idx].aiState = result.1

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
                apps[idx].isMyApp = record.isMyApp
                apps[idx].isFavorite = record.isFavorite
                apps[idx].isSubscribed = record.hasSubscription
                apps[idx].isAnalysisLocked = record.isAnalysisLocked
            }
        }
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

    private func refreshUpdates(for scannedApps: [AppInfo], token: UUID) async {
        await updateChecker.resetHomebrewCache()

        for app in scannedApps where !app.version.isEmpty && app.canCheckForUpdates {
            let acknowledgedVersion = cacheService?.load(bundleID: app.bundleID)?.acknowledgedUpdateVersion
            let state = await updateChecker.check(app: app, acknowledgedVersion: acknowledgedVersion)
            guard token == updateScanToken,
                  let idx = apps.firstIndex(where: { $0.bundleID == app.bundleID }) else {
                continue
            }
            apps[idx].updateState = state
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
