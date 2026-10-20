import Testing
import Foundation
import SwiftData
@testable import Sift

/// Quick wins from the 2026-10-20 code review.

@Suite("CSV formula guard")
struct CSVFormulaGuardTests {
    @Test("A field starting with = + - @ opens as text, not a formula")
    func formulaPrefixes() {
        #expect(CSVExporter.field("=HYPERLINK(\"http://x\")") == "\"'=HYPERLINK(\"\"http://x\"\")\"")
        #expect(CSVExporter.field("+1") == "'+1")
        #expect(CSVExporter.field("-2") == "'-2")
        #expect(CSVExporter.field("@SUM(A1)") == "'@SUM(A1)")
        #expect(CSVExporter.field("\tcmd") == "'\tcmd")
    }

    @Test("Ordinary fields are untouched")
    func ordinaryFields() {
        #expect(CSVExporter.field("Raycast") == "Raycast")
        #expect(CSVExporter.field("4") == "4")
        #expect(CSVExporter.field("") == "")
        #expect(CSVExporter.field("a=b") == "a=b")
    }
}

@Suite("Legacy licence key sweep")
@MainActor
struct LegacyLicenseSweepTests {
    private func viewModel(with keys: [String: String]) throws -> (AppListViewModel, ModelContainer) {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        for (bundleID, key) in keys {
            let record = AppRecord(stub: bundleID, appName: bundleID)
            record.licenseKey = key
            container.mainContext.insert(record)
        }
        let viewModel = AppListViewModel()
        viewModel.cacheService = CacheService(context: container.mainContext)
        return (viewModel, container)
    }

    private func freshDefaults(_ name: String) -> UserDefaults {
        let suite = "SiftTests.LegacyLicenseSweep.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("A key the Keychain refused keeps the sweep open for next launch")
    func refusedKeyRetries() throws {
        let (viewModel, container) = try viewModel(with: ["com.example.a": "KEY-A"])
        let defaults = freshDefaults("refused")
        viewModel.migrateLegacyLicenseKeys(store: LicenseKeyStore(backend: DroppingSecretStoreBackend()), defaults: defaults)
        #expect(!defaults.bool(forKey: "didMigrateLegacyLicenseKeys"))
        let record = try #require(try container.mainContext.fetch(FetchDescriptor<AppRecord>()).first)
        #expect(record.licenseKey == "KEY-A")
    }

    @Test("Once every key moved, the sweep is marked done")
    func allMovedMarksDone() throws {
        let (viewModel, container) = try viewModel(with: ["com.example.a": "KEY-A", "com.example.b": "KEY-B"])
        let defaults = freshDefaults("moved")
        let backend = MemorySecretStoreBackend()
        viewModel.migrateLegacyLicenseKeys(store: LicenseKeyStore(backend: backend), defaults: defaults)
        #expect(defaults.bool(forKey: "didMigrateLegacyLicenseKeys"))
        #expect(backend.read(account: "com.example.b") == "KEY-B")
        let records = try container.mainContext.fetch(FetchDescriptor<AppRecord>())
        #expect(records.allSatisfy { $0.licenseKey == nil && $0.hasLicenseKey })
    }
}
