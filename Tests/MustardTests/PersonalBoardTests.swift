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

    func test_recentDone_capsByCount_newestFirst_mineOnly() {
        func done(_ title: String, at ts: TimeInterval, owner: TaskOwner = .me) -> MustardTask {
            let t = MustardTask(title: title, owner: owner)
            t.markDone(now: Date(timeIntervalSince1970: ts))
            return t
        }
        let d1 = done("d1", at: 100)
        let d2 = done("d2", at: 200)
        let d3 = done("d3", at: 300)
        let agent = done("agent", at: 999, owner: .agent)
        let open = MustardTask(title: "open"); open.status = .planned

        // limit 2 → the two newest of mine, agent excluded
        let result = PersonalBoard.recentDone([d1, d3, d2, agent, open], limit: 2)
        XCTAssertEqual(result.map(\.title), ["d3", "d2"])
    }

    func test_olderDoneCount_isMineDoneBeyondLimit() {
        func done(_ title: String, at ts: TimeInterval) -> MustardTask {
            let t = MustardTask(title: title)
            t.markDone(now: Date(timeIntervalSince1970: ts))
            return t
        }
        let tasks = [done("a", at: 1), done("b", at: 2), done("c", at: 3), done("d", at: 4)]
        XCTAssertEqual(PersonalBoard.olderDoneCount(tasks, limit: 2), 2)
        // fewer done than the limit → nothing older
        XCTAssertEqual(PersonalBoard.olderDoneCount([done("x", at: 1)], limit: 2), 0)
    }
}
