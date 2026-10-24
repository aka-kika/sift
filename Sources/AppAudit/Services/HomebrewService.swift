import Foundation

struct HomebrewCaskInfo: Equatable, Sendable {
    let token: String
    let latestVersion: String?
}

/// `failed` means brew did not answer (missing, or a non-zero exit). That is
/// not the same as an empty outdated list, which means every cask is current.
enum HomebrewOutdatedAnswer: Equatable, Sendable {
    case list([HomebrewCaskInfo])
    case failed
}

struct HomebrewService: Sendable {
    func installedCasks() -> [String] {
        runBrew(arguments: ["list", "--cask"])
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Reads stdout alone: brew prints warnings on stderr, and one warning in
    /// the same pipe broke the JSON, so every cask read Up to date.
    func outdatedCasks() -> HomebrewOutdatedAnswer {
        let outcome = runBrewChecked(arguments: ["outdated", "--cask", "--json=v2"], mergeStandardError: false)
        return Self.outdatedAnswer(exitStatus: outcome.exitStatus, standardOutput: Data(outcome.output.utf8))
    }

    /// A non-zero exit or JSON that does not decode is a failed check, never
    /// an empty list.
    static func outdatedAnswer(exitStatus: Int32?, standardOutput: Data) -> HomebrewOutdatedAnswer {
        guard exitStatus == 0, let casks = decodeOutdatedCasks(from: standardOutput) else { return .failed }
        return .list(casks)
    }

    func upgradeCask(_ token: String) -> BrewOutcome {
        runBrewChecked(arguments: ["upgrade", "--cask", token])
    }

    /// What Run Update tells the user. brew upgrade updates only the copy brew
    /// installed, so a hand-installed copy matched by name is not handed to
    /// brew, and brew's exit status, not its output, says whether it worked.
    enum UpgradeReport {
        static let notBrewsCopy = "This copy was not installed by Homebrew, so brew upgrade would not update it. Update it from the app or its website."

        static func message(for outcome: BrewOutcome) -> String {
            guard outcome.succeeded else { return "Homebrew could not update it. \(outcome.message)" }
            let output = outcome.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let done = "Homebrew finished. Rescan to refresh this app's version."
            return output.isEmpty ? done : done + "\n\n" + output
        }
    }

    /// What `brew` actually did. `exitStatus` is nil when brew could not be run at all.
    struct BrewOutcome: Sendable {
        let exitStatus: Int32?
        let output: String
        var succeeded: Bool { exitStatus == 0 }
        /// Something to show the user when it failed.
        var message: String {
            if exitStatus == nil { return "Homebrew is not installed or could not be run." }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "brew exited with status \(exitStatus ?? -1)." : trimmed
        }
    }

    /// Runs `brew uninstall --cask <token>` and reports whether it worked — brew's
    /// exit status, not the presence of output, is the verdict.
    func uninstall(cask token: String) -> BrewOutcome {
        runBrewChecked(arguments: ["uninstall", "--cask", token])
    }

    func caskToken(forAppName appName: String, path: String, installedCasks: [String]) -> String? {
        if let token = Self.caskTokenFromCaskroomPath(path) {
            return token
        }

        let normalizedLookup = Dictionary(
            installedCasks.map { (Self.normalizedToken($0), $0) },
            uniquingKeysWith: { first, _ in first }   // "x-beta" and "x@beta" normalise alike
        )

        let appNameCandidate = Self.normalizedToken(appName)
        if let token = normalizedLookup[appNameCandidate] {
            return token
        }

        let pathName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return normalizedLookup[Self.normalizedToken(pathName)]
    }

    static func parseOutdatedCasks(from data: Data) -> [HomebrewCaskInfo] {
        decodeOutdatedCasks(from: data) ?? []
    }

    static func decodeOutdatedCasks(from data: Data) -> [HomebrewCaskInfo]? {
        guard let response = try? JSONDecoder().decode(HomebrewOutdatedResponse.self, from: data) else {
            return nil
        }

        return response.casks.map {
            HomebrewCaskInfo(
                token: $0.name,
                latestVersion: $0.currentVersion
            )
        }
    }

    // MARK: - Does this bundle belong to the cask?

    /// Where Homebrew keeps installed casks, Apple silicon first.
    static let caskroomRoots = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]

    /// True only when brew's own install record says this cask put an app at
    /// `bundlePath`. `caskToken(forAppName:)` also matches by name, which is
    /// fine for showing an update but not for `brew uninstall`: a manual copy
    /// or a beta named like the cask would have brew remove the other copy.
    /// No record, or one that cannot be read, means no.
    static func caskOwnsBundle(token: String, bundlePath: String,
                               caskroomRoots: [String] = caskroomRoots) -> Bool {
        let bundle = canonicalPath(bundlePath)
        for root in caskroomRoots {
            let caskDir = (root as NSString).appendingPathComponent(token)
            // An app brew left inside the Caskroom is the cask's by location.
            if bundle.hasPrefix(canonicalPath(caskDir) + "/") { return true }
            let metadata = (caskDir as NSString).appendingPathComponent(".metadata")
            guard let receipt = FileManager.default.contents(
                atPath: (metadata as NSString).appendingPathComponent("INSTALL_RECEIPT.json")) else { continue }
            let config = FileManager.default.contents(
                atPath: (metadata as NSString).appendingPathComponent("config.json"))
            let appdir = installedAppdir(fromConfig: config)
            if appPaths(fromReceipt: receipt, appdir: appdir).map(canonicalPath).contains(bundle) {
                return true
            }
        }
        return false
    }

    /// The appdir the cask was installed with: an explicit `--appdir` wins over
    /// brew's default, and brew's own default is /Applications.
    static func installedAppdir(fromConfig data: Data?) -> String {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "/Applications"
        }
        let explicit = (json["explicit"] as? [String: Any])?["appdir"] as? String
        let fallback = (json["default"] as? [String: Any])?["appdir"] as? String
        return explicit ?? fallback ?? "/Applications"
    }

    /// The `.app` paths in an INSTALL_RECEIPT's `uninstall_artifacts`. An `app`
    /// artifact is `["Source.app"]` or `["Source.app", {"target": "Name.app"}]`;
    /// the source may sit in a subfolder of the download, the installed name is
    /// its last component, and a relative target lands in the appdir.
    static func appPaths(fromReceipt data: Data, appdir: String) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artifacts = json["uninstall_artifacts"] as? [[String: Any]] else { return [] }
        return artifacts.compactMap { artifact -> String? in
            guard let entry = artifact["app"] as? [Any],
                  let source = entry.first as? String else { return nil }
            let target = entry.dropFirst()
                .compactMap { ($0 as? [String: Any])?["target"] as? String }
                .first
            let name = target ?? (source as NSString).lastPathComponent
            let expanded = (name as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") { return expanded }
            return ((appdir as NSString).expandingTildeInPath as NSString).appendingPathComponent(expanded)
        }
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func caskTokenFromCaskroomPath(_ path: String) -> String? {
        let components = URL(fileURLWithPath: path).standardized.pathComponents
        guard let index = components.firstIndex(of: "Caskroom"),
              components.indices.contains(index + 1) else {
            return nil
        }
        return components[index + 1]
    }

    /// The environment one brew run gets. `brew outdated` is on Homebrew's
    /// auto-update list: left alone it runs `brew update` first, which fetches
    /// for many seconds and changes the user's Homebrew during a read-only
    /// check. So the checks Sift runs by itself turn auto-update off.
    /// `brew upgrade` keeps it: the user asked for the update, and brew should
    /// fetch the current cask before installing it, as it does in Terminal.
    static func environment(for arguments: [String], base: [String: String]) -> [String: String] {
        var environment = base
        if let command = arguments.first, checkCommands.contains(command) {
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        }
        return environment
    }

    private static let checkCommands: Set<String> = ["list", "outdated"]

    /// `mergeStandardError: false` discards stderr for callers that parse
    /// stdout; an unread second pipe would fill at 64 KB and block brew.
    private func runBrewChecked(arguments: [String], mergeStandardError: Bool = true) -> BrewOutcome {
        guard let brewPath = Self.brewExecutablePath() else { return BrewOutcome(exitStatus: nil, output: "") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = arguments
        process.environment = Self.environment(for: arguments, base: ProcessInfo.processInfo.environment)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = mergeStandardError ? pipe : FileHandle.nullDevice
        do {
            try process.run()
            // Drain before waiting: a chatty brew would otherwise fill the pipe and hang.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return BrewOutcome(exitStatus: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
        } catch {
            return BrewOutcome(exitStatus: nil, output: error.localizedDescription)
        }
    }

    private func runBrew(arguments: [String]) -> String {
        guard let brewPath = Self.brewExecutablePath() else { return "" }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = arguments
        process.environment = Self.environment(for: arguments, base: ProcessInfo.processInfo.environment)

        // Callers parse stdout (JSON, cask lists), so stderr is discarded rather
        // than piped: an unread pipe fills at 64 KB and brew blocks forever on it.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            // Drain before waiting, for the same reason.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func brewExecutablePath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private static func normalizedToken(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

private struct HomebrewOutdatedResponse: Decodable {
    let casks: [HomebrewOutdatedCask]
}

private struct HomebrewOutdatedCask: Decodable {
    let name: String
    let currentVersion: String?

    enum CodingKeys: String, CodingKey {
        case name
        case currentVersion = "current_version"
    }
}
