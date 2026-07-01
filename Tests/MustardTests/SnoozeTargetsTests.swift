import XCTest
@testable import MustardKit

/// Snooze / schedule target times — one tested source of truth for the "1 hour / this
/// evening / tomorrow" and next-9am defaults that the triage surfaces (desktop console,
/// mobile sheet + deck) and AgentService.decide(.scheduled) all use. Pinned UTC.
final class SnoozeTargetsTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); return f.date(from: iso)!
    }

    func test_nextNineAM_todayWhenBeforeNine() {
        let now = date("2026-07-01T08:00:00Z")
        XCTAssertEqual(SnoozeTargets.nextNineAM(after: now, calendar: utc), date("2026-07-01T09:00:00Z"))
    }

    func test_nextNineAM_tomorrowWhenAtOrAfterNine() {
        let now = date("2026-07-01T09:00:00Z")
        XCTAssertEqual(SnoozeTargets.nextNineAM(after: now, calendar: utc), date("2026-07-02T09:00:00Z"))
    }

    func test_tomorrow9_isAlwaysNextDayNine() {
        let now = date("2026-07-01T06:00:00Z")
        XCTAssertEqual(SnoozeTargets.tomorrow9(after: now, calendar: utc), date("2026-07-02T09:00:00Z"))
    }

    func test_evening_isSevenPMWhenEarlier() {
        let now = date("2026-07-01T10:00:00Z")
        XCTAssertEqual(SnoozeTargets.evening(after: now, calendar: utc), date("2026-07-01T19:00:00Z"))
    }

    func test_evening_atLeastAMinuteOutWhenPastSevenPM() {
        let now = date("2026-07-01T20:00:00Z")
        XCTAssertEqual(SnoozeTargets.evening(after: now, calendar: utc), date("2026-07-01T20:01:00Z"))
    }
}
