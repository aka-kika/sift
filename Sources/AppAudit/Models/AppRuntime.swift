import Foundation

/// What an app is built with — the framework that draws its windows.
///
/// An audit fact in its own right: a 400 MB menu-bar helper reads differently
/// once you know it ships a whole browser. Nil on `AppInfo` means Sift could
/// not tell, and the fact is left out rather than guessed.
///
/// The idea and the marker rules come from DuoUpdater
/// (https://github.com/jizhi0v0/duo-updater, MIT License) — see
/// `AppRuntimeDetector` for which parts.
enum AppRuntime: String, Sendable, Equatable, CaseIterable {
    case electron
    case tauri
    case flutter
    case qt
    case java
    case chromium
    case catalyst
    case swiftUI
    case appKit

    /// Short label for the facts row.
    var label: String {
        switch self {
        case .electron: return "Electron"
        case .tauri: return "Tauri"
        case .flutter: return "Flutter"
        case .qt: return "Qt"
        case .java: return "Java"
        case .chromium: return "Chromium"
        case .catalyst: return "Mac Catalyst"
        case .swiftUI: return "Native (SwiftUI)"
        case .appKit: return "Native (AppKit)"
        }
    }

    /// One plain sentence for the analysis prompt and tooltips.
    var summary: String {
        switch self {
        case .electron: return "Electron — a web app bundled with its own Chromium browser and Node.js."
        case .tauri: return "Tauri — a web interface in the system WebKit with a Rust core; small on disk."
        case .flutter: return "Flutter — Google's cross-platform UI toolkit, drawn by its own engine."
        case .qt: return "Qt — a cross-platform C++ toolkit."
        case .java: return "Java — runs on a bundled Java runtime."
        case .chromium: return "Embeds the Chromium browser engine (CEF) for its interface."
        case .catalyst: return "Mac Catalyst — an iPad app brought to the Mac."
        case .swiftUI: return "A native Mac app built on SwiftUI."
        case .appKit: return "A native Mac app built on AppKit."
        }
    }

    /// True when the app carries its own UI runtime instead of Apple's.
    var bundlesOwnRuntime: Bool {
        switch self {
        case .electron, .flutter, .qt, .java, .chromium: return true
        case .tauri, .catalyst, .swiftUI, .appKit: return false
        }
    }
}
