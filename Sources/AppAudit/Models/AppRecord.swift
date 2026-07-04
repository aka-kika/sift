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
    var hasSubscription: Bool = false
    var hasLicenseKey: Bool = false
    var licenseEmail: String? = nil
    var subscriptionPrice: Double? = nil
    var subscriptionCurrency: String? = nil
    var subscriptionCycle: String? = nil
    var subscriptionRenewalDate: Date? = nil
    var subscriptionEmail: String? = nil
    var isPaidApp: Bool = false
    var isFreeApp: Bool = false
    var licenseType: String? = nil
    var iconPNG: Data? = nil
    var isAnalysisLocked: Bool = false
    var appURL: String? = nil
    var suggestedAppURL: String? = nil
    var analysisAppURL: String? = nil
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
        self.isFavorite = false
        self.hasSubscription = false
        self.hasLicenseKey = false
        self.licenseEmail = nil
        self.subscriptionPrice = nil
        self.subscriptionCurrency = nil
        self.subscriptionCycle = nil
        self.subscriptionRenewalDate = nil
        self.subscriptionEmail = nil
        self.isPaidApp = false
        self.isFreeApp = false
        self.licenseType = nil
        self.iconPNG = nil
        self.isAnalysisLocked = false
        self.suggestedAppURL = nil
        self.analysisAppURL = nil
        self.acknowledgedUpdateVersion = nil
        self.licenseKey = nil
    }
}
