import XCTest
@testable import MustardKit

final class PersonalBoardTests: XCTestCase {
    func test_tasks_filtersByStatusAndOwner() {
        let a = MustardTask(title: "a"); a.status = .planned
        let b = MustardTask(title: "b"); b.status = .planned
        let inboxMine = MustardTask(title: "inbox-mine")
        let agentPlanned = MustardTask(title: "agent", owner: .agent); agentPlanned.status = .planned

        let planned = PersonalBoard.tasks([a, b, inboxMine, agentPlanned], status: .planned)
        XCTAssertEqual(Set(planned.map(\.title)), ["a", "b"])
        XCTAssertFalse(planned.contains { $0.owner == .agent })

        let inbox = PersonalBoard.tasks([a, b, inboxMine, agentPlanned], status: .inbox)
        XCTAssertEqual(inbox.map(\.title), ["inbox-mine"])
    }

    func test_move_toDone_stampsCompletion() {
        let t = MustardTask(title: "x"); t.status = .planned
        PersonalBoard.move(t, to: .done)
        XCTAssertEqual(t.status, .done)
        XCTAssertNotNil(t.completedAt)
    }

    func test_move_outOfDone_clearsCompletion() {
        let t = MustardTask(title: "x"); t.markDone()
        PersonalBoard.move(t, to: .inProgress)
        XCTAssertEqual(t.status, .inProgress)
        XCTAssertNil(t.completedAt)
    }

    func test_columns_orderedInboxToSomeday() {
        XCTAssertEqual(PersonalBoard.columns, [.inbox, .planned, .inProgress, .done, .someday])
    }
}
