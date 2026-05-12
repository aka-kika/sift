import SwiftData
import Foundation

@Model
final class AppRecord {
    @Attribute(.unique) var bundleID: String
    var appName: String
    var explanation: String
    var relevanceScore: Int
    var relevanceReason: String
    var generatedAt: Date
    var ollamaModel: String
    var bestUse: String?
    var userDescription: String?
    var notes: String?
    var isMyApp: Bool = false
    var isFavorite: Bool = false
    var appURL: String? = nil
    var acknowledgedUpdateVersion: String? = nil
    // Migration-only bridge for older stores. New writes go to Keychain via LicenseKeyStore.
    var licenseKey: String? = nil

    init(bundleID: String, appName: String, explanation: String,
         relevanceScore: Int, relevanceReason: String,
         bestUse: String, ollamaModel: String) {
        self.bundleID = bundleID
        self.appName = appName
        self.explanation = explanation
        self.relevanceScore = relevanceScore
        self.relevanceReason = relevanceReason
        self.bestUse = bestUse.isEmpty ? nil : bestUse
        self.generatedAt = Date()
        self.ollamaModel = ollamaModel
        self.userDescription = nil
        self.notes = nil
        self.isMyApp = false
        self.acknowledgedUpdateVersion = nil
        self.licenseKey = nil
    }
}
