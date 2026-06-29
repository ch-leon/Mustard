import XCTest
@testable import MustardKit

final class CalendarWindowTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testRollingFloorsToStartOfTodayAndSpansDays() {
        let cal = utc
        let now = Date(timeIntervalSince1970: 1_780_000_000)   // some mid-day instant
        let w = CalendarWindow.rolling(from: now, days: 14, calendar: cal)

        // Start is midnight UTC of `now`'s day.
        XCTAssertEqual(w.start, cal.startOfDay(for: now))
        let comps = cal.dateComponents([.hour, .minute, .second], from: w.start)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(comps.second, 0)

        // End is exactly 14 days after start (no DST in UTC) and `now` is inside [start, end).
        XCTAssertEqual(w.end, cal.date(byAdding: .day, value: 14, to: w.start))
        XCTAssertEqual(w.end.timeIntervalSince(w.start), 14 * 86_400)
        XCTAssertLessThanOrEqual(w.start, now)
        XCTAssertLessThan(now, w.end)
    }
}
