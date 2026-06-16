import XCTest
@testable import MustardKit

final class SourceDedupeTests: XCTestCase {
    private func proposal(
        event: String, item: String, action: String = "draft_email", source: SourceID = .gmail
    ) -> SourceProposal {
        SourceProposal(source: source, sourceItemID: item, sourceEventID: event,
                       title: "t", actionType: action)
    }

    private func existing(
        event: String?, item: String?, action: String = "draft_email",
        pending: Bool, source: String = "gmail"
    ) -> Recommendation {
        let r = Recommendation(title: "x", actionType: action, source: source)
        r.sourceEventID = event
        r.sourceItemID = item
        r.decision = pending ? .pending : .denied
        return r
    }

    func test_exactEvent_rejected_evenWhenExistingIsDecided() {
        let recs = [existing(event: "msg-1", item: "thread-1", pending: false)]
        XCTAssertFalse(SourceDedupe.shouldInsert(proposal(event: "msg-1", item: "thread-1"), against: recs),
                       "the same external event must never re-surface, decided or not")
    }

    func test_newEvent_sameItemAndAction_pendingExisting_rejected() {
        let recs = [existing(event: "msg-1", item: "thread-1", pending: true)]
        XCTAssertFalse(SourceDedupe.shouldInsert(proposal(event: "msg-2", item: "thread-1"), against: recs),
                       "rule 2 collapses un-triaged duplicates of the same item+action")
    }

    func test_newEvent_sameItemAndAction_decidedExisting_allowed() {
        // The key fix: once an item is decided, a genuinely new event still surfaces.
        let recs = [existing(event: "msg-1", item: "thread-1", pending: false)]
        XCTAssertTrue(SourceDedupe.shouldInsert(proposal(event: "msg-2", item: "thread-1"), against: recs))
    }

    func test_brandNewEvent_allowed() {
        XCTAssertTrue(SourceDedupe.shouldInsert(proposal(event: "msg-9", item: "thread-9"), against: []))
    }

    func test_sameItemAndAction_differentSource_allowed() {
        let recs = [existing(event: "h1", item: "thread-1", pending: true, source: "vault")]
        XCTAssertTrue(SourceDedupe.shouldInsert(proposal(event: "msg-2", item: "thread-1", source: .gmail), against: recs))
    }
}
