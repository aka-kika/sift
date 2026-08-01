import SwiftUI
import SwiftData
#if canImport(AppKit)
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
    }
}
#endif

@main
struct AppAuditApp: App {
    @State private var viewModel = AppListViewModel()
    @AppStorage("appearancePreference") private var appearancePreference = "system"
    @AppStorage("developerMode") private var developerMode = false
    #if canImport(AppKit)
    @NSApplicationDelegateAdaptor(SiftAppDelegate.self) private var appDelegate
    #endif

    private static let container: ModelContainer = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeDir = appSupport.appendingPathComponent(Self.dataFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let storeURL = storeDir.appendingPathComponent("AppAudit.store")
        let config = ModelConfiguration(url: storeURL)
        return try! ModelContainer(for: AppRecord.self, configurations: config)
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
                #if canImport(AppKit)
                .onChange(of: appearancePreference) { _, newValue in
                    AppAppearance.apply(newValue)
                }
                #endif
        }
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentMinSize)
        .modelContainer(Self.container)
        .commands {
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
