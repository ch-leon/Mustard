import XCTest
@testable import MustardKit

final class DelegationPhaseTests: XCTestCase {
    func test_notDelegated_isNone() {
        XCTAssertEqual(
            DelegationPhase.resolve(isDelegated: false, executionState: nil,
                                    decision: nil, latestReview: nil, taskDone: false),
            .none)
    }

    func test_queuedForApproval_isProposed() {
        XCTAssertEqual(
            DelegationPhase.resolve(isDelegated: true, executionState: .idle,
                                    decision: .pending, latestReview: nil, taskDone: false),
            .proposed)
    }

    func test_running_isWorking() {
        XCTAssertEqual(
            DelegationPhase.resolve(isDelegated: true, executionState: .running,
                                    decision: .approved, latestReview: nil, taskDone: false),
            .working)
    }

    func test_finishedWithPendingOutput_isAwaitingReview() {
        XCTAssertEqual(
            DelegationPhase.resolve(isDelegated: true, executionState: .finished,
                                    decision: .approved, latestReview: .pending, taskDone: false),
            .awaitingReview)
    }

    func test_taskDone_isDone() {
        XCTAssertEqual(
            DelegationPhase.resolve(isDelegated: true, executionState: .finished,
                                    decision: .approved, latestReview: .accepted, taskDone: true),
            .done)
    }

    func test_tone_none_isNil() {
        XCTAssertNil(DelegationPhase.none.tone)
    }

    func test_tone_proposedAndAwaitingReview_areNeedsYou() {
        XCTAssertEqual(DelegationPhase.proposed.tone, .needsYou)
        XCTAssertEqual(DelegationPhase.awaitingReview.tone, .needsYou)
    }

    func test_tone_working_isAgentHasIt() {
        XCTAssertEqual(DelegationPhase.working.tone, .agentHasIt)
    }

    func test_tone_done_isDoneByAgent() {
        XCTAssertEqual(DelegationPhase.done.tone, .doneByAgent)
    }

    func test_awaitingReviewLabel_isYourTurn() {
        XCTAssertEqual(DelegationPhase.awaitingReview.label, "Your turn")
    }
}
