import Testing
import Foundation
@testable import Sift

/// The 10 Nov review fixes (Runway card "Sift": 5d16, 5745, 380e, 5486, b3b1).

@Suite("Copy Key from the right-click menu does not open an empty License panel (5d16)")
struct CopyKeyPanelTests {
    @Test("The panel comes back after Touch ID only when it was open")
    func reopensOnlyWhenOpen() {
        #expect(CopyKeyPanel.reopensAfterCopy(panelWasOpen: true))
        #expect(!CopyKeyPanel.reopensAfterCopy(panelWasOpen: false))
    }
}
