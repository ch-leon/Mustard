import XCTest
@testable import MustardKit

final class RecommendationQueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func rec(action: String = "vault_note", decision: RecommendationDecision = .pending,
                     snooze: Date? = nil) -> Recommendation {
        let r = Recommendation(title: "x", actionType: action)
        r.decision = decision
        r.snoozedUntil = snooze
        return r
    }

    func test_excludesIgnore() {
        XCTAssertTrue(RecommendationQueue.pending([rec(action: "ignore")], now: now).isEmpty)
    }

    func test_keepsPendingVaultNoteAndFyi() {
        let recs = [rec(action: "vault_note"), rec(action: "fyi")]
        XCTAssertEqual(RecommendationQueue.pending(recs, now: now).count, 2)
    }

    func test_excludesFutureSnoozed_keepsDueSnoozed() {
        let future = rec(snooze: now.addingTimeInterval(3600))
        let due = rec(snooze: now.addingTimeInterval(-1))
        let out = RecommendationQueue.pending([future, due], now: now)
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out.contains { $0 === due })
    }

    func test_excludesDecided() {
        let recs = [rec(decision: .approved), rec(decision: .denied)]
        XCTAssertTrue(RecommendationQueue.pending(recs, now: now).isEmpty)
    }
}
