import XCTest
@testable import MustardKit

final class DayPlannerTests: XCTestCase {
    // Pin the calendar to UTC so ISO "Z" fixtures bucket deterministically
    // regardless of the machine's timezone (AEST is +10: 15:00Z is tomorrow).
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func test_tasksForDay_returnsOnlySameDayScheduled_sortedByTime() {
        let day = at("2026-06-12T00:00:00Z")
        let a = MustardTask(title: "late", scheduledAt: at("2026-06-12T15:00:00Z"))
        let b = MustardTask(title: "early", scheduledAt: at("2026-06-12T09:00:00Z"))
        let other = MustardTask(title: "tomorrow", scheduledAt: at("2026-06-13T09:00:00Z"))
        let unscheduled = MustardTask(title: "loose")
        let result = DayPlanner.tasksForDay([a, b, other, unscheduled], day: day, calendar: cal)
        XCTAssertEqual(result.map(\.title), ["early", "late"])
    }

    func test_unscheduled_returnsOpenTasksWithNoDate() {
        let scheduled = MustardTask(title: "s", scheduledAt: at("2026-06-12T09:00:00Z"))
        let open = MustardTask(title: "open")
        let done = MustardTask(title: "done")
        done.markDone()
        let result = DayPlanner.unscheduled([scheduled, open, done])
        XCTAssertEqual(result.map(\.title), ["open"])
    }

    func test_carryForward_movesIncompletePastTasksToToday_preservingTimeOfDay() {
        let today = at("2026-06-12T00:00:00Z")
        let stale = MustardTask(title: "stale", scheduledAt: at("2026-06-10T14:30:00Z"))
        let doneStale = MustardTask(title: "doneStale", scheduledAt: at("2026-06-10T14:30:00Z"))
        doneStale.markDone()
        DayPlanner.carryForward([stale, doneStale], to: today, calendar: cal)

        let comps = cal.dateComponents([.day, .hour, .minute], from: stale.scheduledAt!)
        XCTAssertEqual(comps.day, 12)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertEqual(doneStale.scheduledAt, at("2026-06-10T14:30:00Z"))
    }

    func test_upcoming_returnsOpenScheduledAfterNow_soonestFirst_limited() {
        let now = at("2026-06-12T10:00:00Z")
        let soon = MustardTask(title: "soon", scheduledAt: at("2026-06-12T11:00:00Z"))
        let later = MustardTask(title: "later", scheduledAt: at("2026-06-12T15:00:00Z"))
        let past = MustardTask(title: "past", scheduledAt: at("2026-06-12T09:00:00Z"))
        let done = MustardTask(title: "done", scheduledAt: at("2026-06-12T12:00:00Z")); done.markDone()
        let unsched = MustardTask(title: "unsched")
        let result = DayPlanner.upcoming([later, soon, past, done, unsched], after: now, limit: 2)
        XCTAssertEqual(result.map(\.title), ["soon", "later"])
    }

    func test_carryForward_leavesTodayAndFutureTasksAlone() {
        let today = at("2026-06-12T00:00:00Z")
        let todays = MustardTask(title: "today", scheduledAt: at("2026-06-12T09:00:00Z"))
        let future = MustardTask(title: "future", scheduledAt: at("2026-06-14T09:00:00Z"))
        DayPlanner.carryForward([todays, future], to: today, calendar: cal)
        XCTAssertEqual(todays.scheduledAt, at("2026-06-12T09:00:00Z"))
        XCTAssertEqual(future.scheduledAt, at("2026-06-14T09:00:00Z"))
    }
}
