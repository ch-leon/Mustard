import XCTest
@testable import MustardKit

/// Review-focus mode (BAK-101) collapses the board to exactly the two gate columns.
final class BoardFocusTests: XCTestCase {
    func test_gateStages_areTheTwoGates_inPipelineOrder() {
        XCTAssertEqual(PersonalBoard.gateStages, [.needsApproval, .needsReview])
    }
}
