import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppListViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("developerMode") private var developerMode = false
    @State private var storeOpenIssue = AppAuditApp.storeOpenIssue

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            if let message = SaveFailures.shared.message {
                saveFailedBanner(message)
            }
            if viewModel.staleModelCount > 0 {
                modelChangedBanner
            }

            NavigationSplitView {
                // Wide enough for Sort, Search and the sidebar button side by side.
                AppListView()
                    .navigationSplitViewColumnWidth(min: 290, ideal: 300, max: 360)
            } detail: {
                if let selectedID = viewModel.selectedAppID,
                   let app = viewModel.apps.first(where: { $0.id == selectedID }) {
                    // One view per installed copy: no @State (record, drafts,
                    // license key) can carry over from the previous selection.
                    AppDetailView(app: app)
                        .id(app.id)
                } else {
                    emptyDetailView
                }
            }
        }
        .plainWindowToolbar()
        .overlay(alignment: .top) {
            if viewModel.showingSearchPalette {
                ZStack(alignment: .top) {
                    // A click outside closes the palette.
                    Color.black.opacity(0.001)
                        .onTapGesture { viewModel.showingSearchPalette = false }
                    SearchPalette()
                        .padding(.top, 72)
                }
            }
        }
        .background {
            // ⌘K opens search too; ⌘F is the View menu's item.
            Button("") { viewModel.showingSearchPalette = true }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if case .enriching(let done, let total) = viewModel.scanState {
                    Text("Analyzing \(done)/\(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            let priorRecords = (try? modelContext.fetchCount(FetchDescriptor<AppRecord>())) ?? 0
            if WhatsNew.shouldShow(hasPriorRecords: priorRecords > 0) {
                viewModel.whatsNewLines = WhatsNew.notes(for: WhatsNew.currentVersion)
            }
            viewModel.cacheService = CacheService(context: modelContext)
            viewModel.migrateDefaultProfileToAutomatic()
            viewModel.migrateStyleNotesKey()
            viewModel.migrateLegacyLicenseKeys()
            viewModel.syncLicenseFlags()
            await viewModel.runFullScan()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Settings writes the provider and model straight to UserDefaults.
            viewModel.recomputeStaleModelCount()
        }
        .sheet(isPresented: Binding(
            get: { viewModel.whatsNewLines != nil },
            set: { if !$0 { viewModel.whatsNewLines = nil; WhatsNew.markSeen() } }
        )) {
            WhatsNewSheet(appName: "Sift", lines: viewModel.whatsNewLines ?? []) {
                viewModel.whatsNewLines = nil
                WhatsNew.markSeen()
            }
        }
        .alert(
            storeOpenIssue?.title ?? "",
            isPresented: Binding(
                get: { storeOpenIssue != nil },
                set: { if !$0 { storeOpenIssue = nil } }
            ),
            presenting: storeOpenIssue
        ) { issue in
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([issue.fileURL])
            }
            Button("OK", role: .cancel) {}
        } message: { issue in
            Text(issue.message)
        }
        .onChange(of: developerMode) { _, enabled in
            viewModel.setFilterMyApps(
                (enabled && viewModel.filterMyApps)
            )
        }
    }

    private var modelChangedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(pastelize(.orange, colorScheme))
            Text(modelChangedMessage)
                .font(.callout)
            Spacer(minLength: 8)
            Button("Re-analyze \(viewModel.staleModelCount)") {
                Task { await viewModel.reanalyzeAll(scope: .modelChangedUnlocked) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(pastelize(.orange, colorScheme))
            .disabled(AppListViewModel.ScanCommands.isBusy(viewModel.scanState))
            .help(AppListViewModel.ScanCommands.busyReason)
            Button("Dismiss") {
                viewModel.dismissModelChangeBanner()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func saveFailedBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(pastelize(.red, colorScheme))
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Dismiss") {
                SaveFailures.shared.dismiss()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var modelChangedMessage: String {
        let count = viewModel.staleModelCount
        let noun = count == 1 ? "analysis was" : "analyses were"
        return "\(count) \(noun) generated with a different model. Re-analyze to refresh?"
    }

    @ViewBuilder
    private var emptyDetailView: some View {
        switch viewModel.scanState {
        case .idle, .scanning:
            ContentUnavailableView {
                Label("Scanning Apps", systemImage: "app.badge")
            } description: {
                Text("Sift is reading your installed apps and update sources.")
            } actions: {
                ProgressView()
                    .controlSize(.small)
            }
        default:
            if viewModel.availableUpdateCount > 0 {
                ContentUnavailableView {
                    Label("No App Selected", systemImage: "app.badge")
                } description: {
                    Text(viewModel.sortOrder == .updates ? "Select an app from the update list to review the available version." : updateSummary)
                } actions: {
                    if viewModel.sortOrder != .updates {
                        Button {
                            viewModel.showAvailableUpdates()
                        } label: {
                            Label("View Updates", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                // No Rescan button here: one stray click rescanned everything
                // (Kika, 28 Oct). File > Rescan (⌘R) stays.
                ContentUnavailableView {
                    Label("No App Selected", systemImage: "app.badge")
                } description: {
                    Text("Choose an app from the sidebar to inspect its analysis, notes, links, and update status.")
                }
            }
        }
    }

    private var updateSummary: String {
        let count = viewModel.availableUpdateCount
        let appNoun = count == 1 ? "app has" : "apps have"
        return "\(count) \(appNoun) an available update. Review them from the sidebar."
    }
}
