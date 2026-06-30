import XCTest
@testable import MustardKit

/// Task-to-task dependency (BAK-107): `blockedByTask` + its effect on `isBlocked`.
final class BlockedByTests: XCTestCase {
    func test_isBlocked_trueWhenBlockerIsOpen() {
        let blocker = MustardTask(title: "do first"); blocker.stage = .inProgress
        let t = MustardTask(title: "needs first"); t.blockedByTask = blocker
        XCTAssertTrue(t.isBlocked)
    }

    func test_isBlocked_falseWhenBlockerIsDone() {
        let blocker = MustardTask(title: "did first"); blocker.stage = .done
        let t = MustardTask(title: "now free"); t.blockedByTask = blocker
        XCTAssertFalse(t.isBlocked)
    }

    func test_isBlocked_stillRespectsFreeTextReason() {
        let t = MustardTask(title: "waiting"); t.blockedReason = "awaiting vendor reply"
        XCTAssertTrue(t.isBlocked)
    }

    func test_isBlocked_falseWithNoBlockerAndNoReason() {
        XCTAssertFalse(MustardTask(title: "free").isBlocked)
    }
}
