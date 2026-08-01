import Foundation

struct HomebrewCaskInfo: Equatable, Sendable {
    let token: String
    let installedVersion: String?
    let latestVersion: String?
}

struct HomebrewService: Sendable {
    func installedCasks() -> [String] {
        runBrew(arguments: ["list", "--cask"])
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func outdatedCasks() -> [HomebrewCaskInfo] {
        let output = runBrew(arguments: ["outdated", "--cask", "--json=v2"])
        guard let data = output.data(using: .utf8) else { return [] }
        return Self.parseOutdatedCasks(from: data)
    }

    func upgradeCask(_ token: String) -> String {
        runBrew(arguments: ["upgrade", "--cask", token], includeStandardError: true)
    }

    func uninstallCask(_ token: String) -> String {
        runBrew(arguments: ["uninstall", "--cask", token], includeStandardError: true)
    }

    func caskToken(forAppName appName: String, path: String, installedCasks: [String]) -> String? {
        if let token = Self.caskTokenFromCaskroomPath(path) {
            return token
        }

        let normalizedLookup = Dictionary(
            uniqueKeysWithValues: installedCasks.map { (Self.normalizedToken($0), $0) }
        )

        let appNameCandidate = Self.normalizedToken(appName)
        if let token = normalizedLookup[appNameCandidate] {
            return token
        }

        let pathName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return normalizedLookup[Self.normalizedToken(pathName)]
    }

    static func parseOutdatedCasks(from data: Data) -> [HomebrewCaskInfo] {
        guard let response = try? JSONDecoder().decode(HomebrewOutdatedResponse.self, from: data) else {
            return []
        }

        return response.casks.map {
            HomebrewCaskInfo(
                token: $0.name,
                installedVersion: $0.installedVersions?.first,
                latestVersion: $0.currentVersion
            )
        }
    }

    static func caskTokenFromCaskroomPath(_ path: String) -> String? {
        let components = URL(fileURLWithPath: path).standardized.pathComponents
        guard let index = components.firstIndex(of: "Caskroom"),
              components.indices.contains(index + 1) else {
            return nil
        }
        return components[index + 1]
    }

    private func runBrew(arguments: [String], includeStandardError: Bool = false) -> String {
        guard let brewPath = Self.brewExecutablePath() else { return "" }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = arguments

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard includeStandardError else { return output }

            let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return [output, errorOutput]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
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
    let installedVersions: [String]?
    let currentVersion: String?

    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
    }
}
