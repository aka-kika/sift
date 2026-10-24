import Testing
import Foundation
import AppKit
@testable import Sift

/// Fixes from the 2026-10-25 second check of the 24 Oct review branch.
/// One suite per finding.

@Suite("A change saved during a scan is analyzed after it")
@MainActor
struct QueuedReanalysisTests {
    @Test("A saved link during an analysis waits in the queue instead of being dropped")
    func queuedWhileBusy() async {
        let viewModel = AppListViewModel()
        viewModel.scanState = .enriching(completed: 1, total: 4)
        await viewModel.reanalyze(bundleID: "com.example.notes", appURL: "https://example.com")
        #expect(viewModel.queuedReanalysis.map(\.bundleID) == ["com.example.notes"])
        #expect(viewModel.queuedReanalysis.first?.appURL == "https://example.com")
    }

    @Test("Saving twice keeps one entry with the newest link")
    func newestLinkWins() async {
        let viewModel = AppListViewModel()
        viewModel.scanState = .scanning
        await viewModel.reanalyze(bundleID: "com.example.notes", appURL: "https://old.example.com")
        await viewModel.reanalyze(bundleID: "com.example.other")
        await viewModel.reanalyze(bundleID: "com.example.notes", appURL: "https://new.example.com")
        #expect(viewModel.queuedReanalysis.map(\.bundleID) == ["com.example.other", "com.example.notes"])
        #expect(viewModel.queuedReanalysis.last?.appURL == "https://new.example.com")
    }

    @Test("With no scan running nothing is queued")
    func notQueuedWhenIdle() async {
        let viewModel = AppListViewModel()
        viewModel.scanState = .done
        await viewModel.reanalyze(bundleID: "com.example.notes")
        #expect(viewModel.queuedReanalysis.isEmpty)
    }
}
