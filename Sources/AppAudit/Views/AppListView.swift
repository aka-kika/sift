import SwiftUI

/// The sidebar keeps the app list once one is loaded. A rescan used to
/// replace it with a spinner, which the 1.12.4 notes said it would not do.
/// The spinner is only for the first scan, before any app is loaded.
enum SidebarDuringScan {
    enum Phase: Equatable { case waiting, ready }

    static func showsSpinner(hasApps: Bool, phase: Phase) -> Bool {
        !hasApps && phase == .waiting
    }
}

struct AppListView: View {
    @Environment(AppListViewModel.self) private var viewModel

    private var scanPhase: SidebarDuringScan.Phase {
        switch viewModel.scanState {
        case .idle, .scanning: return .waiting
        case .enriching, .done, .error: return .ready
        }
    }

    var body: some View {
        @Bindable var vm = viewModel

        Group {
            switch viewModel.scanState {
            case .error(let msg):
                ContentUnavailableView("Scan Failed", systemImage: "xmark.circle", description: Text(msg))
            case .idle, .scanning, .enriching, .done:
                if SidebarDuringScan.showsSpinner(hasApps: !viewModel.apps.isEmpty, phase: scanPhase) {
                    ProgressView("Scanning apps\u{2026}")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let emptyState = viewModel.sidebarEmptyState, viewModel.scanState != .scanning {
                    sidebarEmptyView(emptyState)
                } else {
                    List(viewModel.filteredApps, selection: $vm.selectedAppID) { app in
                        AppRow(app: app)
                            .tag(app.id)
                    }
                    .listStyle(.sidebar)
                    .softTopScrollEdge()
                }
            }
        }
        .navigationTitle("Sift")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Sort", selection: Binding(
                    get: { viewModel.sortOrder },
                    set: { viewModel.setSortOrder($0) }
                )) {
                    ForEach(AppListViewModel.SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }
            // Rescan lives in the File menu (⌘R) only: one stray click here
            // rescanned everything (Kika, 28 Oct). Search took its place.
            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.showingSearchPalette = true
                } label: {
                    Label("Search Apps", systemImage: "magnifyingglass")
                }
                .help("Search apps (⌘F or ⌘K)")
            }
        }
        .sheet(isPresented: $vm.showingVault) {
            LicenseVaultView(installedBundleIDs: Set(viewModel.apps.map(\.bundleID)))
        }
    }

    @ViewBuilder
    private func sidebarEmptyView(_ state: AppListViewModel.SidebarEmptyState) -> some View {
        ContentUnavailableView {
            Label(sidebarEmptyTitle(for: state), systemImage: sidebarEmptySystemImage(for: state))
        } description: {
            Text(sidebarEmptyDescription(for: state))
        } actions: {
            sidebarEmptyAction(for: state)
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func sidebarEmptyAction(for state: AppListViewModel.SidebarEmptyState) -> some View {
        switch state {
        case .noResults:
            Button("Clear Search") {
                viewModel.setSearchText("")
            }
        case .noUpdates:
            Button {
                Task { await viewModel.refreshUpdateStatuses() }
            } label: {
                Label(viewModel.isRefreshingUpdates ? "Refreshing Updates" : "Refresh Updates", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isRefreshingUpdates)
        case .noMyApps, .noFavorites:
            Button("Show All Apps") {
                viewModel.clearFilters()
            }
        case .noApps:
            Button {
                Task { await viewModel.runFullScan() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.scanState == .scanning)
        }
    }

    private func sidebarEmptyTitle(for state: AppListViewModel.SidebarEmptyState) -> String {
        switch state {
        case .noApps:
            return "No Apps"
        case .noResults:
            return "No Results"
        case .noUpdates:
            return "No Updates"
        case .noMyApps:
            return "No My Apps"
        case .noFavorites:
            return "No Favorites"
        }
    }

    private func sidebarEmptyDescription(for state: AppListViewModel.SidebarEmptyState) -> String {
        switch state {
        case .noApps:
            return "Run a scan to load installed apps."
        case .noResults:
            return "Nothing matches the current search."
        case .noUpdates:
            return "No available updates are showing right now."
        case .noMyApps:
            return "Mark apps you build or maintain to see them here."
        case .noFavorites:
            return "Favorite apps to keep a short review list."
        }
    }

    private func sidebarEmptySystemImage(for state: AppListViewModel.SidebarEmptyState) -> String {
        switch state {
        case .noApps:
            return "app.badge"
        case .noResults:
            return "magnifyingglass"
        case .noUpdates:
            return "checkmark.circle"
        case .noMyApps:
            return "hammer"
        case .noFavorites:
            return "star"
        }
    }
}
