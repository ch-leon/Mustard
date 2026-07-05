import XCTest
@testable import MustardKit

final class NoteReindexSchedulerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)
    func test_neverIndexed_isDue() {
        XCTAssertTrue(NoteReindexScheduler.isDue(lastIndexedAt: nil, now: t0))
    }
    func test_withinInterval_notDue_afterInterval_due() {
        XCTAssertFalse(NoteReindexScheduler.isDue(lastIndexedAt: t0, now: t0.addingTimeInterval(299)))
        XCTAssertTrue(NoteReindexScheduler.isDue(lastIndexedAt: t0, now: t0.addingTimeInterval(300)))
    }
}
