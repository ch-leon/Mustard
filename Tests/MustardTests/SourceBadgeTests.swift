import XCTest
@testable import MustardKit

final class SourceBadgeTests: XCTestCase {
    func test_gmail_isBadged() {
        let b = SourceBadge.badge(for: .gmail)
        XCTAssertFalse(b.isQuiet)
        XCTAssertEqual(b.label, "Gmail")
    }

    func test_vault_isQuiet() {
        XCTAssertTrue(SourceBadge.badge(for: .vault).isQuiet)
    }

    func test_unknownRaw_fallsBackToQuietVault() {
        XCTAssertTrue(SourceBadge.badge(forRaw: "carrier-pigeon").isQuiet)
    }
}
