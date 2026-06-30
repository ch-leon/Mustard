import XCTest
@testable import MustardKit

/// Today's day-progress derivation (BAK-103): "N of M done" over the tasks scheduled
/// on the day. Pinned UTC calendar + ISO fixtures per CLAUDE.md.
final class DayProgressTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: iso)!
    }

    func test_dayProgress_countsDoneOverTotalForThatDay() {
        let day = date("2026-07-01T00:00:00Z")
        let t1 = MustardTask(title: "open", scheduledAt: date("2026-07-01T09:00:00Z"))
        let t2 = MustardTask(title: "done1", scheduledAt: date("2026-07-01T10:00:00Z"))
        t2.stage = .done
        let t3 = MustardTask(title: "done2", scheduledAt: date("2026-07-01T11:00:00Z"))
        t3.stage = .done
        let otherDay = MustardTask(title: "tomorrow", scheduledAt: date("2026-07-02T09:00:00Z"))

        let p = DayPlanner.dayProgress([t1, t2, t3, otherDay], day: day, calendar: utc)
        XCTAssertEqual(p.done, 2)
        XCTAssertEqual(p.total, 3)
    }

    func test_dayProgress_emptyDay_isZero() {
        let p = DayPlanner.dayProgress([], day: date("2026-07-01T00:00:00Z"), calendar: utc)
        XCTAssertEqual(p.done, 0)
        XCTAssertEqual(p.total, 0)
    }
}
