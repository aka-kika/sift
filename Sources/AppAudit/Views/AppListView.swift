import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#endif

struct AppListView: View {
    @Environment(AppListViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        Group {
            switch viewModel.scanState {
            case .idle, .scanning:
                ProgressView("Scanning apps\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .enriching, .done:
                if let emptyState = viewModel.sidebarEmptyState {
                    sidebarEmptyView(emptyState)
                } else {
                    List(viewModel.filteredApps, selection: $vm.selectedAppID) { app in
                        AppRow(app: app)
                            .tag(app.id)
                    }
                    .listStyle(.sidebar)
                }
            case .error(let msg):
                ContentUnavailableView("Scan Failed", systemImage: "xmark.circle", description: Text(msg))
            }
        }
        .navigationTitle("Sift")
        .searchable(
            text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.setSearchText($0) }
            ),
            prompt: "Search apps"
        )
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
            ToolbarItem(placement: .automatic) {
                Menu {
                    Toggle("My Apps", isOn: Binding(
                        get: { viewModel.filterMyApps },
                        set: { viewModel.setFilterMyApps($0) }
                    ))
                    Toggle("Favorites", isOn: Binding(
                        get: { viewModel.filterFavorites },
                        set: { viewModel.setFilterFavorites($0) }
                    ))
                } label: {
                    Label("Filter", systemImage: (viewModel.filterMyApps || viewModel.filterFavorites)
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task {
                        if viewModel.sortOrder == .updates {
                            await viewModel.refreshUpdateStatuses()
                        } else {
                            await viewModel.runFullScan()
                        }
                    }
                } label: {
                    Label(refreshButtonTitle, systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshButtonDisabled)
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        Task { await viewModel.reanalyzeAll(scope: .allUnlocked) }
                    } label: {
                        Label("Re-analyze All Apps", systemImage: "arrow.clockwise.circle")
                    }
                    .disabled(viewModel.apps.isEmpty)

                    Button {
                        exportCSV()
                    } label: {
                        Label("Export to CSV…", systemImage: "tablecells")
                    }
                    .disabled(viewModel.apps.isEmpty)

                    Divider()

                    Button {
                        viewModel.showingVault = true
                    } label: {
                        Label("License Vault…", systemImage: "key.horizontal")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(viewModel.scanState == .scanning)
            }
        }
        .sheet(isPresented: $vm.showingVault) {
            LicenseVaultView(installedBundleIDs: Set(viewModel.apps.map(\.bundleID)))
        }
    }

    private func exportCSV() {
        #if canImport(AppKit)
        let csv = viewModel.exportCSV()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "AppAudit-\(formatter.string(from: Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.title = "Export Audit to CSV"
        if panel.runModal() == .OK, let url = panel.url {
            try? Data(csv.utf8).write(to: url)
        }
        #endif
    }

    private var refreshButtonTitle: String {
        if viewModel.sortOrder == .updates {
            return viewModel.isRefreshingUpdates ? "Refreshing Updates" : "Refresh Updates"
        }
        return "Rescan"
    }

    private var isRefreshButtonDisabled: Bool {
        viewModel.scanState == .scanning ||
            viewModel.isRefreshingUpdates ||
            (viewModel.sortOrder == .updates && viewModel.apps.isEmpty)
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
