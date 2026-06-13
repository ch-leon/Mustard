import XCTest
@testable import MustardKit

final class TrustPolicyTests: XCTestCase {
    func test_gatedActionTypes() {
        XCTAssertTrue(TrustPolicy.isGated(actionType: "draft_email"))
        XCTAssertTrue(TrustPolicy.isGated(actionType: "ticket_write"))
        XCTAssertTrue(TrustPolicy.isGated(actionType: "draft_slack"))
        XCTAssertFalse(TrustPolicy.isGated(actionType: "vault_note"))
        XCTAssertFalse(TrustPolicy.isGated(actionType: "create_task"))
    }

    func test_lowConfidence_neverAutoRuns_evenTrusted() {
        XCTAssertFalse(TrustPolicy.shouldAutoApprove(actionType: "vault_note", trust: .trusted, confidence: 0.4))
        XCTAssertTrue(TrustPolicy.shouldAutoApprove(actionType: "vault_note", trust: .trusted, confidence: 0.8))
    }

    func test_confidenceThresholdBoundary() {
        XCTAssertTrue(TrustPolicy.shouldAutoApprove(actionType: "vault_note", trust: .supervised, confidence: 0.7))
        XCTAssertFalse(TrustPolicy.shouldAutoApprove(actionType: "vault_note", trust: .supervised, confidence: 0.69))
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
        XCTAssertFalse(TrustPolicy.shouldAutoApprove(actionType: "draft_email", trust: .autonomous))
        XCTAssertFalse(TrustPolicy.shouldAutoAccept(actionType: "draft_email", trust: .autonomous))
    }
}
