import XCTest
@testable import MustardKit

final class TrustPolicyTests: XCTestCase {
    func test_gatedActionTypes() {
        XCTAssertTrue(TrustPolicy.isGated(actionType: "email_send"))
        XCTAssertTrue(TrustPolicy.isGated(actionType: "ticket_write"))
        XCTAssertTrue(TrustPolicy.isGated(actionType: "slack_post"))
        XCTAssertFalse(TrustPolicy.isGated(actionType: "vault_note"))
    }

    func test_manual_neverAutoApproves() {
        XCTAssertFalse(TrustPolicy.shouldAutoApprove(actionType: "vault_note", trust: .manual))
        XCTAssertFalse(TrustPolicy.shouldAutoAccept(actionType: "vault_note", trust: .manual))
    }

    func test_supervised_autoApprovesNonGated_butDoesNotAutoAccept() {
        XCTAssertTrue(TrustPolicy.shouldAutoApprove(actionType: "vault_note", trust: .supervised))
        XCTAssertFalse(TrustPolicy.shouldAutoAccept(actionType: "vault_note", trust: .supervised))
    }

    func test_trusted_autoApprovesAndAutoAcceptsNonGated() {
        XCTAssertTrue(TrustPolicy.shouldAutoApprove(actionType: "vault_note", trust: .trusted))
        XCTAssertTrue(TrustPolicy.shouldAutoAccept(actionType: "vault_note", trust: .trusted))
    }

    func test_gatedNeverAutoRuns_evenAutonomous() {
        XCTAssertFalse(TrustPolicy.shouldAutoApprove(actionType: "email_send", trust: .autonomous))
        XCTAssertFalse(TrustPolicy.shouldAutoAccept(actionType: "email_send", trust: .autonomous))
    }
}
