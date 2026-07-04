import Foundation

/// Extracts grounding evidence from an app's LOCAL project folder — the README
/// and which manifest files are present — so the analysis prompt can describe a
/// private-repo or no-repo app from files the user already has on disk. Reads
/// the folder root only; never recurses, never touches the network.
enum DocsEvidence {
    static let maxReadmeChars = 4000
    static let maxReadmeBytes = 2_000_000

    private static let readmeNames = ["README.md", "README", "README.txt", "README.markdown"]
    private static let manifestNames = [
        "Package.swift", "package.json", "Cargo.toml",
        "pyproject.toml", "go.mod", "Gemfile", "Info.plist"
    ]
    private static let xcodeBundleSuffixes = [".xcodeproj", ".xcworkspace"]

    static func extract(fromFolder path: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let entries = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        let lowerEntries = Set(entries.map { $0.lowercased() })

        var parts: [String] = []

        // README (first case-insensitive match, truncated). Skip pathologically
        // large files rather than reading them on the main thread.
        if let readmeName = readmeNames.first(where: { lowerEntries.contains($0.lowercased()) }),
           let actual = entries.first(where: { $0.lowercased() == readmeName.lowercased() }) {
            let readmeURL = folder.appendingPathComponent(actual)
            let size = (try? fm.attributesOfItem(atPath: readmeURL.path))?[.size] as? Int ?? 0
            if size <= maxReadmeBytes,
               let text = try? String(contentsOf: readmeURL, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let clipped = trimmed.count > maxReadmeChars
                        ? String(trimmed.prefix(maxReadmeChars)) + "…"
                        : trimmed
                    parts.append(clipped)
                }
            }
        }

        // Stack hint — which manifests are present, plus any Xcode project/workspace
        // bundles (these don't have a fixed name, so match by suffix instead).
        var foundManifests = manifestNames.filter { lowerEntries.contains($0.lowercased()) }
        let xcodeBundles = entries.filter { entry in
            let lower = entry.lowercased()
            return xcodeBundleSuffixes.contains { lower.hasSuffix($0) }
        }
        foundManifests.append(contentsOf: xcodeBundles)
        if !foundManifests.isEmpty {
            parts.append("Detected project files: \(foundManifests.joined(separator: ", "))")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
