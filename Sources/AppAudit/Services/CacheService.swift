import SwiftData
import Foundation

@MainActor
final class CacheService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func load(bundleID: String) -> AppRecord? {
        let descriptor = FetchDescriptor<AppRecord>(
            predicate: #Predicate { $0.bundleID == bundleID }
        )
        return try? context.fetch(descriptor).first
    }

    /// The record for `bundleID`, creating an empty one only if none exists. Always
    /// re-fetches: `bundleID` is unique, so inserting a twin would upsert over — and
    /// blank out — an analysis that arrived while a view held a stale `nil`.
    func ensureRecord(bundleID: String, appName: String) -> AppRecord {
        if let existing = load(bundleID: bundleID) { return existing }
        let record = AppRecord(stub: bundleID, appName: appName)
        context.insert(record)
        return record
    }

    func allRecords() -> [AppRecord] {
        (try? context.fetch(FetchDescriptor<AppRecord>())) ?? []
    }

    func isStale(_ record: AppRecord, currentModel: String, currentAppURL: String? = nil) -> Bool {
        if record.isAnalysisLocked {
            return false
        }
        // A model change no longer auto-invalidates analyses — switching models
        // would otherwise silently wipe and regenerate everything. We only treat
        // an analysis as stale when the reference app link it was built from changed.
        // Model drift is surfaced separately (see wasAnalyzedWithDifferentModel)
        // so the user can choose to re-analyze.
        return normalizedURL(record.analysisAppURL) != normalizedURL(currentAppURL)
    }

    /// Read-only: true when this record holds a real analysis produced by a
    /// different model than the one currently selected. Used to offer (not force)
    /// a re-analyze. Locked or empty analyses never count as drifted.
    func wasAnalyzedWithDifferentModel(_ record: AppRecord, currentModel: String) -> Bool {
        guard !record.isAnalysisLocked, !record.explanation.isEmpty else { return false }
        return record.ollamaModel != currentModel
    }

    func save(
        bundleID: String, appName: String,
        explanation: String, score: Int, reason: String,
        bestUse: String, ollamaModel: String, analysisAppURL: String? = nil,
        analyzedAppVersion: String? = nil
    ) {
        if let existing = load(bundleID: bundleID) {
            guard !existing.isAnalysisLocked else { return }
            // Update AI fields in-place to preserve user edits (notes, description, appURL, isMyApp)
            existing.appName = appName
            existing.explanation = explanation
            existing.relevanceScore = score
            existing.relevanceReason = reason
            existing.bestUse = bestUse.isEmpty ? nil : bestUse
            existing.ollamaModel = ollamaModel
            existing.analysisAppURL = normalizedURL(analysisAppURL)
            existing.analyzedAppVersion = analyzedAppVersion
            existing.generatedAt = Date()
        } else {
            let record = AppRecord(
                bundleID: bundleID,
                appName: appName,
                explanation: explanation,
                relevanceScore: score,
                relevanceReason: reason,
                bestUse: bestUse,
                ollamaModel: ollamaModel
            )
            record.analysisAppURL = normalizedURL(analysisAppURL)
            record.analyzedAppVersion = analyzedAppVersion
            context.insert(record)
        }
        context.saveReportingFailure()
    }

    func persist() {
        context.saveReportingFailure()
    }

    /// True when a saved analysis names a different app version than the one
    /// installed now. An analysis with no stored version is left alone.
    nonisolated static func versionIsStale(analyzedVersion: String?, appVersion: String) -> Bool {
        guard let analyzedVersion, !analyzedVersion.isEmpty, !appVersion.isEmpty else { return false }
        return analyzedVersion != appVersion
    }

    nonisolated static func versionNote(analyzedVersion: String?, appVersion: String) -> String? {
        guard versionIsStale(analyzedVersion: analyzedVersion, appVersion: appVersion),
              let analyzedVersion else { return nil }
        return "Written for \(analyzedVersion). This app is now \(appVersion). Re-analyze to refresh it."
    }

    private func normalizedURL(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
