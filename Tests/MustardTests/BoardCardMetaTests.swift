import XCTest
@testable import MustardKit

/// Model support for the board-card meta row (BAK-99): the `urgent` priority the
/// handoff card flags, and the derived `isProposed` state that drives the
/// "✦ Proposed" pill (handoff: agent-proposed tasks land in Inbox flagged Proposed).
final class BoardCardMetaTests: XCTestCase {
    func test_taskPriority_hasUrgent_withLabel() {
        XCTAssertEqual(TaskPriority.urgent.label, "Urgent")
    }

    func test_taskPriority_allCases_orderedLowToUrgent() {
        // Matches the handoff create-form order (Low / Normal / High / Urgent).
        XCTAssertEqual(TaskPriority.allCases, [.low, .normal, .high, .urgent])
    }

    func test_isProposed_trueForAgentInbox() {
        let t = MustardTask(title: "Drafted reply")
        t.owner = .agent
        t.stage = .inbox
        XCTAssertTrue(t.isProposed)
    }

    func test_isProposed_falseForMyInbox() {
        let t = MustardTask(title: "My idea")
        t.owner = .me
        t.stage = .inbox
        XCTAssertFalse(t.isProposed)
    }

    func test_isProposed_falseForAgentNonInbox() {
        let t = MustardTask(title: "Queued work")
        t.owner = .agent
        t.stage = .needsApproval
        XCTAssertFalse(t.isProposed)
    }
}
