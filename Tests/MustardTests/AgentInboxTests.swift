import XCTest
@testable import MustardKit

/// The "waiting on you" count behind the nudge / dock / badge (BAK-104).
final class AgentInboxTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func test_waitingCount_pendingRecsPlusHumanAttentionTasks() {
        let r1 = Recommendation(title: "a") // default: pending, vault_note (not ignored)
        let r2 = Recommendation(title: "b")
        let question = MustardTask(title: "answer me"); question.stage = .needsInput
        let review = MustardTask(title: "review me"); review.stage = .needsReview
        let other = MustardTask(title: "planned"); other.stage = .planned

        XCTAssertEqual(
            AgentInbox.waitingCount(recommendations: [], tasks: [question, review], now: now),
            2
        )
        let n = AgentInbox.waitingCount(
            recommendations: [r1, r2], tasks: [question, review, other], now: now
        )
        XCTAssertEqual(n, 4) // 2 pending recs + 2 tasks needing human attention
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

    // MARK: dock text (BAK-106)

    func test_dockText_allClearWhenEmpty() {
        XCTAssertEqual(AgentInbox.dockText(recs: 0, outputs: 0), "All clear — nothing waiting on you")
    }

    func test_dockText_recsOnly_pluralizes() {
        XCTAssertEqual(AgentInbox.dockText(recs: 1, outputs: 0), "1 recommendation waiting on you")
        XCTAssertEqual(AgentInbox.dockText(recs: 2, outputs: 0), "2 recommendations waiting on you")
    }

    func test_dockText_outputsOnly() {
        XCTAssertEqual(AgentInbox.dockText(recs: 0, outputs: 1), "1 output waiting on you")
    }

    func test_dockText_both() {
        XCTAssertEqual(AgentInbox.dockText(recs: 1, outputs: 3), "1 recommendation and 3 outputs waiting on you")
    }
}
