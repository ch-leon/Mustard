import XCTest
@testable import MustardKit

final class RecurrenceEngineTests: XCTestCase {
    // Pin UTC so weekday/clamp math is deterministic regardless of machine zone.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func test_daily_addsOneDay() {
        XCTAssertEqual(
            RecurrenceEngine.nextDate(.daily, after: at("2026-06-12T09:00:00Z"), calendar: cal),
            at("2026-06-13T09:00:00Z"))
    }

    func test_weekly_addsSevenDays() {
        XCTAssertEqual(
            RecurrenceEngine.nextDate(.weekly, after: at("2026-06-12T09:00:00Z"), calendar: cal),
            at("2026-06-19T09:00:00Z"))
    }

    func test_weekdays_fridaySkipsToMonday() {
        // 2026-06-12 is a Friday → Monday 2026-06-15
        XCTAssertEqual(
            RecurrenceEngine.nextDate(.weekdays, after: at("2026-06-12T09:00:00Z"), calendar: cal),
            at("2026-06-15T09:00:00Z"))
    }

    func test_weekdays_midweekAddsOneDay() {
        // 2026-06-10 is a Wednesday → Thursday 2026-06-11
        XCTAssertEqual(
            RecurrenceEngine.nextDate(.weekdays, after: at("2026-06-10T09:00:00Z"), calendar: cal),
            at("2026-06-11T09:00:00Z"))
    }

    func test_monthly_clampsToLastValidDay() {
        // Jan 31 + 1 month → Feb 28 (2026 is not a leap year)
        XCTAssertEqual(
            RecurrenceEngine.nextDate(.monthly, after: at("2026-01-31T09:00:00Z"), calendar: cal),
            at("2026-02-28T09:00:00Z"))
    }
}
