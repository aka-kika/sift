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

    func isStale(_ record: AppRecord, currentModel: String) -> Bool {
        // Invalidate when the selected analysis provider or model changes.
        return record.ollamaModel != currentModel
    }

    func save(
        bundleID: String, appName: String,
        explanation: String, score: Int, reason: String,
        bestUse: String, ollamaModel: String
    ) {
        if let existing = load(bundleID: bundleID) {
            // Update AI fields in-place to preserve user edits (notes, description, appURL, isMyApp)
            existing.appName = appName
            existing.explanation = explanation
            existing.relevanceScore = score
            existing.relevanceReason = reason
            existing.bestUse = bestUse.isEmpty ? nil : bestUse
            existing.ollamaModel = ollamaModel
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
            context.insert(record)
        }
        try? context.save()
    }

    func delete(bundleID: String) {
        if let record = load(bundleID: bundleID) {
            context.delete(record)
            try? context.save()
        }
    }

    func insert(_ record: AppRecord) {
        context.insert(record)
    }

    func persist() {
        try? context.save()
    }
}
