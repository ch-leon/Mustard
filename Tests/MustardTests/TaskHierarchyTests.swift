import XCTest
@testable import MustardKit

final class TaskHierarchyTests: XCTestCase {
    func test_assigningSelfAsParent_isCycle() {
        let t = MustardTask(title: "t")
        XCTAssertTrue(TaskHierarchy.wouldCreateCycle(assigning: t, to: t))
    }

    func test_assigningDescendantAsParent_isCycle() {
        let a = MustardTask(title: "a")
        let b = MustardTask(title: "b"); b.parent = a
        let c = MustardTask(title: "c"); c.parent = b
        // Making a's parent = c would loop a → c → b → a.
        XCTAssertTrue(TaskHierarchy.wouldCreateCycle(assigning: c, to: a))
    }

    func test_assigningUnrelatedParent_isSafe() {
        let a = MustardTask(title: "a")
        let b = MustardTask(title: "b")
        XCTAssertFalse(TaskHierarchy.wouldCreateCycle(assigning: b, to: a))
    }
}
