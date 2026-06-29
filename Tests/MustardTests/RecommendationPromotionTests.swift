import XCTest
@testable import MustardKit

final class RecommendationPromotionTests: XCTestCase {
    func test_approve_outwardAction_goesToQueuedAgentOwned() {
        let p = RecommendationPromotion.plan(action: .draftEmail, decision: .approved)
        XCTAssertEqual(p.stage, .queued); XCTAssertEqual(p.owner, .agent)
    }
    func test_approve_inVaultAction_goesStraightToDone() {
        let p = RecommendationPromotion.plan(action: .vaultNote, decision: .approved)
        XCTAssertEqual(p.stage, .done); XCTAssertEqual(p.owner, .agent)
    }
    func test_approve_createTask_goesStraightToDone() {
        let p = RecommendationPromotion.plan(action: .createTask, decision: .approved)
        XCTAssertEqual(p.stage, .done); XCTAssertEqual(p.owner, .agent)
    }
    func test_schedule_becomesScheduledMeTask() {
        let p = RecommendationPromotion.plan(action: .draftEmail, decision: .scheduled)
        XCTAssertEqual(p.stage, .scheduled); XCTAssertEqual(p.owner, .me)
    }
    func test_selfExecute_becomesPlannedMeTask() {
        let p = RecommendationPromotion.plan(action: .ticket, decision: .selfExecute)
        XCTAssertEqual(p.stage, .planned); XCTAssertEqual(p.owner, .me)
    }
}
