import XCTest
@testable import MustardKit

final class TaskStageTests: XCTestCase {
    func test_allViews_includeInboxAndDone() {
        for view in BoardOwnerView.allCases {
            XCTAssertTrue(view.columns.contains(.inbox), "\(view) missing inbox")
            XCTAssertTrue(view.columns.contains(.done), "\(view) missing done")
        }
    }

    func test_mineView_hasNoAgentStages() {
        let agentStages: Set<TaskStage> = [.forAgent, .needsApproval, .queued, .needsReview]
        XCTAssertTrue(BoardOwnerView.mine.columns.allSatisfy { !agentStages.contains($0) })
    }

    func test_everyoneView_isTheFullPipelineInOrder() {
        XCTAssertEqual(BoardOwnerView.everyone.columns,
            [.inbox, .planned, .scheduled, .forAgent, .needsApproval,
             .queued, .needsReview, .inProgress, .blocked, .done])
    }

    func test_agentView_columns() {
        XCTAssertEqual(BoardOwnerView.agent.columns,
            [.inbox, .forAgent, .needsApproval, .queued, .needsReview, .done])
    }

    func test_kind_perStage() {
        XCTAssertEqual(TaskStage.forAgent.kind, .handoff)
        XCTAssertEqual(TaskStage.needsApproval.kind, .gate)
        XCTAssertEqual(TaskStage.queued.kind, .agent)
        XCTAssertEqual(TaskStage.needsReview.kind, .gate)
        XCTAssertEqual(TaskStage.blocked.kind, .warn)
        XCTAssertEqual(TaskStage.done.kind, .done)
        XCTAssertEqual(TaskStage.planned.kind, .standard)
    }
}
