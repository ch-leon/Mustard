import XCTest
@testable import MustardKit

/// The "waiting on you" count behind the nudge / dock / badge (BAK-104).
final class AgentInboxTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func test_waitingCount_pendingRecsPlusNeedsReviewTasks() {
        let r1 = Recommendation(title: "a") // default: pending, vault_note (not ignored)
        let r2 = Recommendation(title: "b")
        let review = MustardTask(title: "review me"); review.stage = .needsReview
        let other = MustardTask(title: "planned"); other.stage = .planned

        let n = AgentInbox.waitingCount(recommendations: [r1, r2], tasks: [review, other], now: now)
        XCTAssertEqual(n, 3) // 2 pending recs + 1 needsReview task
    }

    func test_waitingCount_excludesSnoozedRecs() {
        let snoozed = Recommendation(title: "later")
        snoozed.snoozedUntil = now.addingTimeInterval(3600)
        let n = AgentInbox.waitingCount(recommendations: [snoozed], tasks: [], now: now)
        XCTAssertEqual(n, 0)
    }

    func test_waitingCount_emptyIsZero() {
        XCTAssertEqual(AgentInbox.waitingCount(recommendations: [], tasks: [], now: now), 0)
    }
}
