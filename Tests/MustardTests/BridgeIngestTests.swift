import XCTest
@testable import MustardKit

final class BridgeIngestTests: XCTestCase {
    private func task(_ stage: TaskStage, uid: String = "u1") -> MustardTask {
        let t = MustardTask(title: "t"); t.uid = uid; t.stage = stage; return t
    }
    private func result(mode: String, status: String, links: [TaskLink]? = nil,
                        actionType: String? = nil, body: String? = nil, summary: String? = nil) -> AgentResult {
        AgentResult(uid: "u1", mode: mode, status: status, actionType: actionType,
                    title: nil, body: body, links: links, summary: summary, error: nil)
    }

    func test_executeDone_setsLinks_andNeedsReview() {
        let t = task(.queued)
        let out = BridgeIngest.apply(result(mode: "execute", status: "done",
            links: [TaskLink(label: "Shortcut", url: "https://app.shortcut.com/x")], summary: "made it"), to: t)
        XCTAssertEqual(out, .applied)
        XCTAssertEqual(t.stage, .needsReview)
        XCTAssertEqual(t.links.first?.url, "https://app.shortcut.com/x")
    }

    func test_prepDone_setsDraftAndAction_andNeedsApproval() {
        let t = task(.forAgent)
        let out = BridgeIngest.apply(result(mode: "prep", status: "done",
            actionType: "ticket_write", body: "prepared"), to: t)
        XCTAssertEqual(out, .applied)
        XCTAssertEqual(t.stage, .needsApproval)
        XCTAssertEqual(t.actionType, .ticket)
        XCTAssertEqual(t.notes, "prepared")
    }

    func test_staleStage_isIgnored_notApplied() {
        let t = task(.done)   // task already moved on
        let out = BridgeIngest.apply(result(mode: "execute", status: "done",
            links: [TaskLink(label: "x", url: "y")]), to: t)
        XCTAssertEqual(out, .staleIgnored)
        XCTAssertEqual(t.stage, .done)   // untouched
    }

    func test_doubleApply_isNoOp() {
        let t = task(.queued)
        let r = result(mode: "execute", status: "done", links: [TaskLink(label: "x", url: "y")])
        XCTAssertEqual(BridgeIngest.apply(r, to: t), .applied)      // → needsReview
        XCTAssertEqual(BridgeIngest.apply(r, to: t), .staleIgnored) // stage no longer queued
    }

    func test_unknownTask_isUnknown() {
        XCTAssertEqual(BridgeIngest.apply(result(mode: "execute", status: "done"), to: nil), .unknownTask)
    }

    func test_executeFailed_staysQueued() {
        let t = task(.queued)
        let out = BridgeIngest.apply(result(mode: "execute", status: "failed"), to: t)
        XCTAssertEqual(out, .applied)
        XCTAssertEqual(t.stage, .queued)   // left for retry
    }

    func test_prepDeclined_returnsToMe() {
        let t = task(.forAgent)
        _ = BridgeIngest.apply(result(mode: "prep", status: "declined", summary: "not mine"), to: t)
        XCTAssertEqual(t.owner, .me)
        XCTAssertEqual(t.stage, .planned)
    }
}
