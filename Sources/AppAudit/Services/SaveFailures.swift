import SwiftData
import Foundation
import Observation

/// A failed save (full disk, read-only store) used to look saved and was gone
/// after relaunch. Every save reports here, and the window shows a small
/// banner until it is dismissed.
@MainActor
@Observable
final class SaveFailures {
    static let shared = SaveFailures()

    private(set) var message: String?

    func report(_ error: Error) {
        message = Self.text(for: error)
    }

    func dismiss() {
        message = nil
    }

    nonisolated static func text(for error: Error) -> String {
        "Sift could not save a change (\(error.localizedDescription)). It will be gone after Sift quits. Check that the disk has free space."
    }
}

extension ModelContext {
    /// `save()` that says so when it fails, instead of `try?`.
    @MainActor
    func saveReportingFailure(to failures: SaveFailures? = nil) {
        do {
            try save()
        } catch {
            (failures ?? .shared).report(error)
        }
    }
}
