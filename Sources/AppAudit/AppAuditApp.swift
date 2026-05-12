import SwiftUI
import SwiftData

@main
struct AppAuditApp: App {
    @State private var viewModel = AppListViewModel()
    private static let container: ModelContainer = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeDir = appSupport.appendingPathComponent("AppAudit", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let storeURL = storeDir.appendingPathComponent("AppAudit.store")
        let config = ModelConfiguration(url: storeURL)
        return try! ModelContainer(for: AppRecord.self, configurations: config)
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .frame(minWidth: 780, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .modelContainer(Self.container)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan Apps") {
                    Task { await viewModel.runFullScan() }
                }
                .keyboardShortcut("R", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}
