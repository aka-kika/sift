import SwiftUI

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
                List(viewModel.filteredApps, selection: $vm.selectedAppID) { app in
                    AppRow(app: app)
                        .tag(app.id)
                }
                .listStyle(.sidebar)
            case .error(let msg):
                ContentUnavailableView("Scan Failed", systemImage: "xmark.circle", description: Text(msg))
            }
        }
        .navigationTitle("AppAudit")
        .searchable(
            text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ),
            prompt: "Search apps"
        )
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Sort", selection: Binding(
                    get: { viewModel.sortOrder },
                    set: { viewModel.sortOrder = $0 }
                )) {
                    ForEach(AppListViewModel.SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await viewModel.runFullScan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.scanState == .scanning)
            }
        }
    }
}
