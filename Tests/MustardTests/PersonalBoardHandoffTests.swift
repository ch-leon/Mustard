import XCTest
@testable import MustardKit

/// BAK-90: a task can only be handed off to the agent once it has a client area —
/// the bridge export filters by area, so an area-less hand-off would silently never
/// route. `canHandOffToAgent` is the pure gate the views + AgentService.delegate check.
final class PersonalBoardHandoffTests: XCTestCase {
    func test_canHandOff_falseWhenNoList() {
        XCTAssertFalse(PersonalBoard.canHandOffToAgent(MustardTask(title: "x")))
    }

    func test_canHandOff_falseWhenListHasNoArea() {
        let t = MustardTask(title: "x")
        t.list = TaskList(name: "loose")   // area-less list
        XCTAssertFalse(PersonalBoard.canHandOffToAgent(t))
    }

    func test_canHandOff_trueWithArea() {
        let t = MustardTask(title: "x")
        t.list = TaskList(name: "DL", area: Area(name: "Digital Licence"))
        XCTAssertTrue(PersonalBoard.canHandOffToAgent(t))
    }
}
