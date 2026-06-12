import Foundation
import LocalAuthentication

/// Gates license-key access behind the system authentication sheet — Touch ID,
/// Apple Watch, or the account password. The system UI is the point: it is what
/// makes the protection legible and trustworthy. Never replace it with a custom
/// password dialog.
enum LicenseKeyGuard {
    /// One authentication per call — every copy or reveal re-authenticates.
    /// Fails closed when no authentication method is available.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
