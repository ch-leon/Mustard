import XCTest
@testable import MustardKit

final class BridgeExportTests: XCTestCase {
    private func task(_ stage: TaskStage, uid: String, action: RecommendationAction? = nil) -> MustardTask {
        let t = MustardTask(title: "t-\(uid)"); t.uid = uid; t.stage = stage
        if let action { t.actionType = action }
        return t
    }
    private let target = BridgeExport.RouteTarget(workingDir: "/kb/DL", project: "DL")
    private func route(_ t: MustardTask) -> BridgeExport.RouteTarget? { target }
    private let now = Date(timeIntervalSince1970: 1)

    func test_queuedTask_withoutOutbox_writesExecuteOrder() {
        let plan = BridgeExport.plan(tasks: [task(.queued, uid: "u1", action: .ticket)],
                                     route: route, liveOutboxUIDs: [:], now: now)
        XCTAssertEqual(plan.writes.count, 1)
        XCTAssertEqual(plan.writes[0].workingDir, "/kb/DL")
        XCTAssertEqual(plan.writes[0].order.uid, "u1")
        XCTAssertEqual(plan.writes[0].order.mode, "execute")
        XCTAssertEqual(plan.writes[0].order.actionType, "ticket_write")
        XCTAssertTrue(plan.cancels.isEmpty)
    }

    func test_forAgentTask_writesPrepOrder() {
        let plan = BridgeExport.plan(tasks: [task(.forAgent, uid: "u2")],
                                     route: route, liveOutboxUIDs: [:], now: now)
        XCTAssertEqual(plan.writes.first?.order.mode, "prep")
    }

    func test_taskWithLiveOutbox_isSkipped() {
        let plan = BridgeExport.plan(tasks: [task(.queued, uid: "u1")],
                                     route: route, liveOutboxUIDs: ["/kb/DL": ["u1"]], now: now)
        XCTAssertTrue(plan.writes.isEmpty)
    }

    func test_nonAgentStage_isIgnored() {
        let plan = BridgeExport.plan(tasks: [task(.planned, uid: "u3")],
                                     route: route, liveOutboxUIDs: [:], now: now)
        XCTAssertTrue(plan.writes.isEmpty)
    }

    func test_staleOutbox_isCancelled() {
        // live outbox u9, but no forAgent/queued task for it → cancel
        let plan = BridgeExport.plan(tasks: [task(.queued, uid: "u1")],
                                     route: route, liveOutboxUIDs: ["/kb/DL": ["u1", "u9"]], now: now)
        XCTAssertEqual(plan.cancels, [BridgeExport.Cancel(workingDir: "/kb/DL", uid: "u9")])
    }
}
