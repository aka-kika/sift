import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppListViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            if viewModel.staleModelCount > 0 {
                modelChangedBanner
            }

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
            viewModel.migrateDefaultProfileToAutomatic()
            viewModel.migrateLegacyLicenseKeys()
            viewModel.syncLicenseFlags()
            await viewModel.applyFirstRunProviderDefault()
            await viewModel.runFullScan()
        }
    }

    private var modelChangedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.orange)
            Text(modelChangedMessage)
                .font(.callout)
            Spacer(minLength: 8)
            Button("Re-analyze \(viewModel.staleModelCount)") {
                Task { await viewModel.reanalyzeAll(scope: .modelChangedUnlocked) }
            }
            .glassProminentButtonStyle()
            .controlSize(.small)
            .tint(.orange)
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
