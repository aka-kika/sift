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

@Suite("Update checks on scan")
struct UpdateChecksOnScanTests {
    @Test("On by default, off once turned off")
    func defaultAndOff() {
        let suite = "SiftTests.UpdateChecksOnScan"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #expect(AppListViewModel.checksUpdatesOnScan(defaults: defaults))
        defaults.set(false, forKey: AppListViewModel.checkUpdatesOnScanKey)
        #expect(!AppListViewModel.checksUpdatesOnScan(defaults: defaults))
    }
}

@Suite("Renewal anchor day")
struct RenewalAnchorTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test("A Jan 31 renewal comes back to the 31st after February")
    func monthEndKeepsAnchor() {
        let stored = date(2026, 1, 31)
        let feb = SubscriptionMath.nextRenewal(from: stored, cycle: .monthly, now: date(2026, 2, 10), calendar: utc)
        #expect(utc.component(.day, from: feb) == 28)
        let mar = SubscriptionMath.nextRenewal(from: stored, cycle: .monthly, now: date(2026, 3, 10), calendar: utc)
        #expect(utc.component(.month, from: mar) == 3 && utc.component(.day, from: mar) == 31)
    }

    @Test("A Feb 29 yearly renewal comes back to the 29th in a leap year")
    func leapYearAnchor() {
        let stored = date(2024, 2, 29)
        let next = SubscriptionMath.nextRenewal(from: stored, cycle: .yearly, now: date(2027, 6, 1), calendar: utc)
        #expect(utc.component(.year, from: next) == 2028 && utc.component(.day, from: next) == 29)
    }
}
