import Testing
import Foundation
import SQLite3
@testable import Sift

/// Fixes from the 2026-10-20 code review.

@Suite("Default Ollama model")
struct DefaultOllamaModelTests {
    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "SiftTests.DefaultOllamaModel.\(name)")!
        defaults.removePersistentDomain(forName: "SiftTests.DefaultOllamaModel.\(name)")
        return defaults
    }

    @Test("The default is the public model the README tells you to pull")
    func publicDefault() {
        #expect(OllamaDefaults.model == "llama3.2:latest")
        #expect(!OllamaDefaults.model.contains("kika"))
    }

    @Test("A Mac without the default switches to its first installed chat model")
    func picksInstalledModel() {
        let defaults = freshDefaults("picks")
        #expect(AnalysisProviderKind.ollama.modelToSelect(from: ["mistral:latest", "qwen3:8b"], userDefaults: defaults) == "mistral:latest")
    }

    @Test("Embedding models are skipped when picking")
    func skipsEmbeddingModels() {
        let defaults = freshDefaults("embed")
        #expect(AnalysisProviderKind.ollama.modelToSelect(from: ["nomic-embed-text:latest", "gemma3:4b"], userDefaults: defaults) == "gemma3:4b")
    }

    @Test("A stored model that is installed is kept, with or without :latest")
    func keepsInstalledChoice() {
        let defaults = freshDefaults("keeps")
        #expect(AnalysisProviderKind.ollama.modelToSelect(from: ["llama3.2:latest", "mistral:latest"], userDefaults: defaults) == nil)
        defaults.set("mistral", forKey: "ollamaModel")
        #expect(AnalysisProviderKind.ollama.modelToSelect(from: ["llama3.2:latest", "mistral:latest"], userDefaults: defaults) == nil)
    }

    @Test("No installed models leaves the choice alone")
    func emptyList() {
        let defaults = freshDefaults("empty")
        #expect(AnalysisProviderKind.ollama.modelToSelect(from: [], userDefaults: defaults) == nil)
    }
}

@Suite("Workflow digest privacy")
struct WorkflowDigestPrivacyTests {
    private func app(_ name: String, lastUsed: Date? = nil, running: Bool = false) -> AppInfo {
        AppInfo(
            id: "com.test.\(name)", name: name, version: "1.0",
            bundleID: "com.test.\(name)", path: "/Applications/\(name).app",
            humanReadableDescription: nil, sparkleFeedURL: nil,
            isAppStoreInstall: false, icon: nil,
            category: "public.app-category.developer-tools", lastUsedDate: lastUsed, isRunning: running
        )
    }

    @Test("A cloud prompt carries counts and categories, no app names")
    func noNamesForCloud() {
        let apps = [app("Xcode", lastUsed: Date(), running: true), app("Ghostty", lastUsed: Date())]
        let digest = WorkflowDigest.build(from: apps, includeAppNames: false)
        #expect(digest == "Installed apps: 2. Categories: Developer Tools (2).")
        #expect(!digest.contains("Xcode"))
        #expect(!digest.contains("Ghostty"))
    }

    @Test("A model on this Mac still gets recent and open apps")
    func namesForLocal() {
        let digest = WorkflowDigest.build(from: [app("Xcode", lastUsed: Date(), running: true)], includeAppNames: true)
        #expect(digest.contains("Most recently used: Xcode."))
        #expect(digest.contains("Open right now: Xcode."))
    }

    @Test("Only Ollama on localhost counts as this Mac")
    func localDetection() {
        let defaults = UserDefaults(suiteName: "SiftTests.WorkflowDigestPrivacy.local")!
        defaults.removeObject(forKey: "ollamaBaseURL")
        #expect(AnalysisProviderKind.ollama.runsOnThisMac(userDefaults: defaults))
        #expect(!AnalysisProviderKind.gemini.runsOnThisMac(userDefaults: defaults))
        defaults.set("https://ollama.com", forKey: "ollamaBaseURL")
        #expect(!AnalysisProviderKind.ollama.runsOnThisMac(userDefaults: defaults))
    }
}

@Suite("Data store recovery")
struct DataStoreRecoveryTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftTests-DataStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeSQLite(at url: URL) {
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        sqlite3_exec(db, "CREATE TABLE t(x INTEGER); INSERT INTO t VALUES (1);", nil, nil, nil)
        sqlite3_close(db)
    }

    @Test("A healthy SQLite file is not corrupt, so it is never moved")
    func healthyFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("AppAudit.store")
        makeSQLite(at: store)
        #expect(!DataStoreRecovery.isCorrupt(storeURL: store))
    }

    @Test("A file that is not a database is corrupt")
    func garbageFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("AppAudit.store")
        try Data(repeating: 0x5A, count: 8192).write(to: store)
        #expect(DataStoreRecovery.isCorrupt(storeURL: store))
    }

    @Test("A missing file is not corrupt")
    func missingFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!DataStoreRecovery.isCorrupt(storeURL: dir.appendingPathComponent("AppAudit.store")))
    }

    @Test("Setting aside moves the store and its -wal and -shm, deleting nothing")
    func setAsideMovesAll() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("AppAudit.store")
        for suffix in ["", "-wal", "-shm"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent("AppAudit.store" + suffix))
        }
        let moved = try #require(DataStoreRecovery.setAside(storeURL: store, now: Date(timeIntervalSince1970: 0)))
        #expect(moved.lastPathComponent == "AppAudit.store.broken-1970-01-01T00-00-00Z")
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(FileManager.default.fileExists(atPath: moved.path + "-wal"))
        #expect(FileManager.default.fileExists(atPath: moved.path + "-shm"))
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test("The alert names the set-aside file")
    func alertNamesFile() {
        let url = URL(fileURLWithPath: "/tmp/AppAudit/AppAudit.store.broken-1970-01-01T00-00-00Z")
        #expect(DataStoreOpenIssue.setAside(url).message.contains("AppAudit.store.broken-1970-01-01T00-00-00Z"))
        #expect(DataStoreOpenIssue.leftInPlace(url).message.contains("not saved"))
    }
}
