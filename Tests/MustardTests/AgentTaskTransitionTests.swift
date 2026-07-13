import XCTest
@testable import MustardKit

final class AgentTaskTransitionTests: XCTestCase {
    func test_decisionMapsCompleteOutcomeMatrix() {
        let expected: [(AgentTurnOutcome, AgentTransitionDecision)] = [
            (
                .needsInput,
                AgentTransitionDecision(
                    taskStage: .needsInput,
                    runState: .needsInput,
                    releasesSlot: true
                )
            ),
            (
                .completed,
                AgentTransitionDecision(
                    taskStage: .needsReview,
                    runState: .completed,
                    releasesSlot: true
                )
            ),
            (
                .requiresConnectedWorker,
                AgentTransitionDecision(
                    taskStage: .queued,
                    runState: .queued,
                    releasesSlot: true,
                    requiresConnectedWorker: true
                )
            ),
            (
                .failed,
                AgentTransitionDecision(
                    taskStage: .queued,
                    runState: .failed,
                    releasesSlot: true
                )
            ),
            (
                .cancelled,
                AgentTransitionDecision(
                    taskStage: .planned,
                    runState: .cancelled,
                    releasesSlot: true
                )
            ),
        ]

        for (outcome, decision) in expected {
            XCTAssertEqual(AgentTaskTransition.decision(for: outcome), decision)
        }
    }
}
