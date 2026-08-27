import SwiftUI
import SwiftData
import AppKit

/// Drives the app-wide appearance through AppKit. SwiftUI's
/// `.preferredColorScheme(nil)` stalls ~1s on the Dark→System transition while it
/// re-resolves the system appearance; setting `NSApp.appearance` reverts instantly.
enum AppAppearance {
    static func apply(_ preference: String) {
        let appearance: NSAppearance?
        switch preference {
        case "light": appearance = NSAppearance(named: .aqua)
        case "dark": appearance = NSAppearance(named: .darkAqua)
        default: appearance = nil   // "system" — instant revert to the OS setting
        }
        NSApplication.shared.appearance = appearance
    }
}

/// Single-window utility behavior: closing the window quits the app instead of
/// leaving a ghost Dock icon with no window to reopen. Also applies the saved
/// appearance at launch so the window opens in the right scheme immediately.
final class SiftAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.apply(UserDefaults.standard.string(forKey: "appearancePreference") ?? "system")
        // Touching the singleton here starts Sparkle's scheduled check at launch.
        _ = UpdateService.shared
    }
}

@main
struct AppAuditApp: App {
    @State private var viewModel = AppListViewModel()
    @AppStorage("appearancePreference") private var appearancePreference = "system"
    @AppStorage("developerMode") private var developerMode = false
    @NSApplicationDelegateAdaptor(SiftAppDelegate.self) private var appDelegate

    private static let container: ModelContainer = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeDir = appSupport.appendingPathComponent(Self.dataFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let storeURL = storeDir.appendingPathComponent("AppAudit.store")
        let config = ModelConfiguration(url: storeURL)
        if let container = try? ModelContainer(for: AppRecord.self, configurations: config) {
            return container
        }
        // The store could not be opened (schema from a newer build, corruption).
        // Set it aside — never delete — and start fresh, so the app still launches
        // and the old data can be recovered by hand.
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-wal", "-shm"] {
            let from = storeDir.appendingPathComponent("AppAudit.store" + suffix)
            let to = storeDir.appendingPathComponent("AppAudit.store.broken-\(stamp)" + suffix)
            try? FileManager.default.moveItem(at: from, to: to)
        }
        do {
            return try ModelContainer(for: AppRecord.self, configurations: config)
        } catch {
            fatalError("Sift cannot open or recreate its data store at \(storeURL.path): \(error)")
        }
    }()

    /// Folder under Application Support for this build's SwiftData store. The side-build
    /// (Sift2 test app) gets an isolated folder so it never touches the primary app's
    /// data; the primary app keeps the historical "AppAudit" folder so existing data
    /// carries across the rename to Sift.
    private static var dataFolderName: String {
        switch Bundle.main.bundleIdentifier {
        case "com.kikaapp.sift2": return "Sift2"
        default: return "AppAudit"
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .frame(minWidth: 720, minHeight: 480)
                .onChange(of: appearancePreference) { _, newValue in
                    AppAppearance.apply(newValue)
                }
        }
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentMinSize)
        .modelContainer(Self.container)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdateService.shared.checkForUpdates()
                }
                .disabled(!UpdateService.shared.isAvailable)
            }
            CommandGroup(after: .newItem) {
                Button("Rescan Apps") {
                    Task { await viewModel.runFullScan() }
                }
                .keyboardShortcut("R", modifiers: .command)

                Button("Re-analyze All Apps") {
                    Task { await viewModel.reanalyzeAll(scope: .allUnlocked) }
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
                .disabled(viewModel.apps.isEmpty)

                Button("Export to CSV…") {
                    viewModel.exportCSVToFile()
                }
                .keyboardShortcut("E", modifiers: .command)
                .disabled(viewModel.apps.isEmpty)

                Button("License Vault…") {
                    viewModel.showingVault = true
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                if developerMode {
                    Toggle("Filter: My Apps", isOn: Binding(
                        get: { viewModel.filterMyApps },
                        set: { viewModel.setFilterMyApps($0) }
                    ))
                }
                Toggle("Filter: Favorites", isOn: Binding(
                    get: { viewModel.filterFavorites },
                    set: { viewModel.setFilterFavorites($0) }
                ))
            }
        }

        Settings {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}
