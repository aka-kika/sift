import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppListViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var vm = viewModel

        NavigationSplitView {
            AppListView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if let selectedID = viewModel.selectedAppID,
               let app = viewModel.apps.first(where: { $0.id == selectedID }) {
                AppDetailView(app: app)
            } else {
                emptyDetailView
            }
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
            viewModel.cacheService = CacheService(context: modelContext)
            await viewModel.runFullScan()
        }
    }

    @ViewBuilder
    private var emptyDetailView: some View {
        switch viewModel.scanState {
        case .idle, .scanning:
            ContentUnavailableView {
                Label("Scanning Apps", systemImage: "app.badge")
            } description: {
                Text("AppAudit is reading your installed apps and update sources.")
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
                            viewModel.sortOrder = .updates
                        } label: {
                            Label("View Updates", systemImage: "arrow.down.app")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No App Selected", systemImage: "app.badge")
                } description: {
                    Text("Choose an app from the sidebar to inspect its analysis, notes, links, and update status.")
                } actions: {
                    Button {
                        Task { await viewModel.runFullScan() }
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
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
