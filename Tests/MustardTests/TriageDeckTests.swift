import XCTest
@testable import MustardKit

/// Pure logic behind the mobile Triage swipe deck (BAK-119): the swipe→outcome mapping
/// (gated recs can never be approved by a swipe — they must be reviewed explicitly) and
/// the trust tap-cycle. The deck view composes these + the tested AgentService decisions.
final class TriageDeckTests: XCTestCase {

    func test_swipeRight_approves() {
        // Gated actions approve too on mobile (approving only queues for the Mac session).
        XCTAssertEqual(TriageDeck.outcome(for: .right), .approve)
    }

    func test_swipeLeft_rejects() {
        XCTAssertEqual(TriageDeck.outcome(for: .left), .reject)
    }

    func test_swipeDown_snoozes() {
        XCTAssertEqual(TriageDeck.outcome(for: .down), .snooze)
    }

    func test_trustLevel_next_cyclesThroughAllAndWraps() {
        XCTAssertEqual(TrustLevel.manual.next, .supervised)
        XCTAssertEqual(TrustLevel.supervised.next, .trusted)
        XCTAssertEqual(TrustLevel.trusted.next, .autonomous)
        XCTAssertEqual(TrustLevel.autonomous.next, .manual) // wraps
    }
}
