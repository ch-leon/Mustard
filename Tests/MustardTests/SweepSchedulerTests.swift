import XCTest
@testable import MustardKit

final class SweepSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func test_neverSwept_isDue() {
        XCTAssertTrue(SweepScheduler.isDue(lastSweptAt: nil, intervalHours: 4, now: now))
    }

    func test_intervalElapsed_isDue() {
        let last = now.addingTimeInterval(-5 * 3600)
        XCTAssertTrue(SweepScheduler.isDue(lastSweptAt: last, intervalHours: 4, now: now))
    }

    func test_withinInterval_notDue() {
        let last = now.addingTimeInterval(-1 * 3600)
        XCTAssertFalse(SweepScheduler.isDue(lastSweptAt: last, intervalHours: 4, now: now))
    }

    func test_intervalZero_meansOff_neverDue() {
        XCTAssertFalse(SweepScheduler.isDue(lastSweptAt: nil, intervalHours: 0, now: now))
        XCTAssertFalse(
            SweepScheduler.isDue(
                lastSweptAt: now.addingTimeInterval(-100 * 3600), intervalHours: 0, now: now)
        )
    }
}
