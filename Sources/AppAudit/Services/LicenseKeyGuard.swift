import Foundation
import LocalAuthentication
import os

/// Gates license-key access behind the system authentication sheet — Touch ID,
/// Apple Watch, or the account password. The system UI is the point: it is what
/// makes the protection legible and trustworthy. Never replace it with a custom
/// password dialog.
enum LicenseKeyGuard {
    private static let log = Logger(subsystem: "com.kikaapp.appaudit", category: "LicenseKeyGuard")

    /// One authentication per call — every copy or reveal re-authenticates.
    /// Fails closed when no authentication method is available.
    ///
    /// Uses the completion-handler API bridged through a continuation rather than
    /// LAContext's native async method: the async variant misbehaved inside the
    /// app on the macOS 27 beta, while the completion form presents reliably.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            log.error("auth unavailable: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
                if let evalError {
                    log.error("auth failed: \(evalError.localizedDescription, privacy: .public)")
                } else {
                    log.info("auth \(success ? "succeeded" : "denied", privacy: .public)")
                }
                continuation.resume(returning: success)
            }
        }
    }
}
