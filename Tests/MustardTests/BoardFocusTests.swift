import XCTest
@testable import MustardKit

/// Review-focus mode (BAK-101) collapses the board to exactly the two gate columns.
final class BoardFocusTests: XCTestCase {
    func test_gateStages_areTheTwoGates_inPipelineOrder() {
        XCTAssertEqual(PersonalBoard.gateStages, [.needsApproval, .needsReview])
    }

    // MARK: Auto-collapse empty columns (BAK-102)

    func test_shouldCollapseEmpty_everyoneEmptyNotExpanded_collapses() {
        XCTAssertTrue(PersonalBoard.shouldCollapseEmpty(view: .everyone, isEmpty: true, expanded: false, reviewFocus: false))
    }

    func test_shouldCollapseEmpty_nonEmpty_doesNot() {
        XCTAssertFalse(PersonalBoard.shouldCollapseEmpty(view: .everyone, isEmpty: false, expanded: false, reviewFocus: false))
    }

    func test_shouldCollapseEmpty_expanded_doesNot() {
        XCTAssertFalse(PersonalBoard.shouldCollapseEmpty(view: .everyone, isEmpty: true, expanded: true, reviewFocus: false))
    }

    func test_shouldCollapseEmpty_mineAndAgentLenses_doNot() {
        XCTAssertFalse(PersonalBoard.shouldCollapseEmpty(view: .mine, isEmpty: true, expanded: false, reviewFocus: false))
        XCTAssertFalse(PersonalBoard.shouldCollapseEmpty(view: .agent, isEmpty: true, expanded: false, reviewFocus: false))
    }

    func test_shouldCollapseEmpty_reviewFocus_doesNot() {
        XCTAssertFalse(PersonalBoard.shouldCollapseEmpty(view: .everyone, isEmpty: true, expanded: false, reviewFocus: true))
    }
}
