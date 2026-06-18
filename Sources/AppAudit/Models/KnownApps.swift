import Foundation

/// One curated, verified fact about a well-known app.
/// `summary` is a single factual sentence (what it is + who uses it) that we
/// trust over anything the model might guess from the name. `url` is the
/// official site / product page.
struct KnownApp: Equatable {
    let url: String
    let summary: String
}

/// A small, hand-curated registry of common apps, keyed by lowercased bundle ID.
///
/// Why this exists: small on-device models (Apple Intelligence) invent app
/// purposes when the scanned metadata is sparse. For apps we already recognize,
/// we hand the model ground truth up front — the official link is prefilled
/// offline and the one-line summary is injected into the prompt as authoritative
/// evidence, which stops the guessing.
///
/// Adding an app is intentionally a one-line edit here — no migration, no rebuild
/// of cached records (re-analyze to apply). Match is by bundle ID only: the most
/// reliable signal, and a wrong/unknown ID simply never matches (harmless).
enum KnownApps {
    static let entries: [String: KnownApp] = [
        "com.noodlesoft.hazel": KnownApp(
            url: "https://www.noodlesoft.com",
            summary: "Hazel watches folders and runs user-defined rules to automatically move, rename, sort, and clean up files on macOS."),
        "com.raycast.macos": KnownApp(
            url: "https://www.raycast.com",
            summary: "Raycast is a keyboard-driven launcher and productivity tool for macOS with extensions, clipboard history, snippets, and window management."),
        "com.knollsoft.rectangle": KnownApp(
            url: "https://rectangleapp.com",
            summary: "Rectangle is a macOS window manager that snaps and resizes windows using keyboard shortcuts and screen-edge dragging."),
        "com.microsoft.vscode": KnownApp(
            url: "https://code.visualstudio.com",
            summary: "Visual Studio Code is a free, extensible source-code editor by Microsoft used by developers for editing, debugging, and Git across many languages."),
        "com.figma.desktop": KnownApp(
            url: "https://www.figma.com",
            summary: "Figma is a collaborative interface-design tool used by designers and product teams for UI design, prototyping, and design systems."),
        "notion.id": KnownApp(
            url: "https://www.notion.so",
            summary: "Notion is an all-in-one workspace for notes, documents, wikis, databases, and project management used by individuals and teams."),
        "com.tinyspeck.slackmacgap": KnownApp(
            url: "https://slack.com",
            summary: "Slack is a team messaging app organizing workplace communication into channels, direct messages, calls, and app integrations."),
        "com.1password.1password": KnownApp(
            url: "https://1password.com",
            summary: "1Password is a password manager that securely stores credentials, passkeys, and secrets and autofills them across apps and browsers."),
        "com.culturedcode.thingsmac": KnownApp(
            url: "https://culturedcode.com/things",
            summary: "Things is a personal task manager and to-do app for macOS built around projects, areas, and the Getting Things Done workflow."),
        "com.macpaw.cleanmymac4": KnownApp(
            url: "https://macpaw.com/cleanmymac",
            summary: "CleanMyMac is a maintenance utility that removes junk files, uninstalls apps, and monitors system health on macOS."),
        "com.googlecode.iterm2": KnownApp(
            url: "https://iterm2.com",
            summary: "iTerm2 is a powerful macOS terminal emulator with split panes, search, autocomplete, and extensive customization for command-line work."),
        "company.thebrowser.browser": KnownApp(
            url: "https://arc.net",
            summary: "Arc is a macOS web browser by The Browser Company organized around spaces, tabs in a sidebar, and built-in productivity features."),
        "dev.zed.zed": KnownApp(
            url: "https://zed.dev",
            summary: "Zed is a high-performance, collaborative code editor written in Rust, focused on speed, multiplayer editing, and an integrated AI assistant."),
        "com.sublimetext.4": KnownApp(
            url: "https://www.sublimetext.com",
            summary: "Sublime Text is a fast, lightweight source-code editor known for its speed, multiple selections, and extensibility via packages."),
        "com.docker.docker": KnownApp(
            url: "https://www.docker.com/products/docker-desktop",
            summary: "Docker Desktop runs and manages Linux containers on macOS, giving developers Docker Engine, CLI, and Kubernetes for building and shipping apps."),
        "md.obsidian": KnownApp(
            url: "https://obsidian.md",
            summary: "Obsidian is a local-first Markdown knowledge base for linked notes, backlinks, and a graph view, popular for personal knowledge management."),
        "com.runningwithcrayons.alfred": KnownApp(
            url: "https://www.alfredapp.com",
            summary: "Alfred is a macOS launcher and automation tool offering app launching, file search, clipboard history, and scriptable workflows."),
        "dev.warp.warp-stable": KnownApp(
            url: "https://www.warp.dev",
            summary: "Warp is a modern, Rust-based terminal for macOS with block-based output, AI command assistance, and editor-style input."),
        "com.postmanlabs.mac": KnownApp(
            url: "https://www.postman.com",
            summary: "Postman is an API development platform for building, testing, documenting, and collaborating on HTTP requests and APIs."),
        "com.spotify.client": KnownApp(
            url: "https://www.spotify.com",
            summary: "Spotify is a music and podcast streaming app for discovering, playing, and organizing audio across personal and curated libraries.")
    ]

    /// Curated facts for this bundle ID, if we recognize it. Case-insensitive.
    static func entry(for bundleID: String) -> KnownApp? {
        entries[bundleID.lowercased()]
    }
}
