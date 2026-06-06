import SwiftUI
import SwiftData

@main
struct AppAuditApp: App {
    @State private var viewModel = AppListViewModel()
    private static let container: ModelContainer = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeDir = appSupport.appendingPathComponent(Self.dataFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let storeURL = storeDir.appendingPathComponent("AppAudit.store")
        let config = ModelConfiguration(url: storeURL)
        return try! ModelContainer(for: AppRecord.self, configurations: config)
    }()

    /// Folder under Application Support for this build's SwiftData store. Side-builds
    /// (e.g. the AppAudit2 test app) get an isolated folder so they never touch the
    /// primary app's data; the primary app keeps the historical "AppAudit" folder.
    private static var dataFolderName: String {
        switch Bundle.main.bundleIdentifier {
        case "com.kikaapp.appaudit2": return "AppAudit2"
        default: return "AppAudit"
        }
    }

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
