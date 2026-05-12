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
                ContentUnavailableView(
                    "Select an App",
                    systemImage: "app.badge",
                    description: Text("Choose an app from the sidebar to see its AI analysis.")
                )
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
}
