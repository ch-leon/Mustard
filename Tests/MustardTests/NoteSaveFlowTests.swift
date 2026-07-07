import XCTest
@testable import MustardKit

final class NoteSaveFlowTests: XCTestCase {
    private func ref(_ path: String) -> NoteRef {
        NoteRef(project: "p", workingDirectory: "/wd", relativePath: path)
    }

    // MARK: - Dirty gate

    func test_cleanNote_doesNotWrite() {
        let plan = NoteSaveFlow.plan(content: "same", baseline: "same",
                                     savedRef: ref("a.md"), currentRef: ref("a.md"))
        XCTAssertFalse(plan.shouldWrite)
        XCTAssertFalse(plan.shouldAdvanceBaseline)
    }

    func test_cleanNote_offScreen_stillDoesNotWrite() {
        // Dirty gate wins even when the saved note is no longer current.
        let plan = NoteSaveFlow.plan(content: "same", baseline: "same",
                                     savedRef: ref("a.md"), currentRef: ref("b.md"))
        XCTAssertFalse(plan.shouldWrite)
        XCTAssertFalse(plan.shouldAdvanceBaseline)
    }

    // MARK: - Baseline-advance rule

    func test_dirtyNote_onScreen_writesAndAdvancesBaseline() {
        // Explicit save / autosave-on-disappear: saved note is the one on screen.
        let plan = NoteSaveFlow.plan(content: "new", baseline: "old",
                                     savedRef: ref("a.md"), currentRef: ref("a.md"))
        XCTAssertTrue(plan.shouldWrite)
        XCTAssertTrue(plan.shouldAdvanceBaseline)
    }

    func test_dirtyNote_offScreen_writesButDoesNotAdvanceBaseline() {
        // Save-on-switch: targets the OLD ref while @State already holds the new one,
        // so the in-view baseline must NOT advance (it belongs to the new note).
        let plan = NoteSaveFlow.plan(content: "new", baseline: "old",
                                     savedRef: ref("a.md"), currentRef: ref("b.md"))
        XCTAssertTrue(plan.shouldWrite)
        XCTAssertFalse(plan.shouldAdvanceBaseline)
    }
}
