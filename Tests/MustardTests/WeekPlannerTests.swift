import XCTest
@testable import MustardKit

final class WeekPlannerTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func test_days_returnsSevenConsecutiveStartingMonday() {
        let days = WeekPlanner.days(weekOffset: 0, reference: at("2026-06-12T12:00:00Z"), calendar: cal)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(cal.component(.weekday, from: days[0]), 2) // Monday
        for i in 1..<7 {
            XCTAssertEqual(
                cal.dateComponents([.day], from: days[i - 1], to: days[i]).day, 1
            )
        }
    }

    func test_days_offsetShiftsBySevenDays() {
        let this = WeekPlanner.days(weekOffset: 0, reference: at("2026-06-12T12:00:00Z"), calendar: cal)
        let next = WeekPlanner.days(weekOffset: 1, reference: at("2026-06-12T12:00:00Z"), calendar: cal)
        XCTAssertEqual(cal.dateComponents([.day], from: this[0], to: next[0]).day, 7)
    }

    func test_unscheduled_excludesScheduledDoneAndAgent() {
        let open = MustardTask(title: "open")
        let sched = MustardTask(title: "s", scheduledAt: at("2026-06-12T09:00:00Z"))
        let done = MustardTask(title: "d"); done.markDone()
        let agent = MustardTask(title: "a", owner: .agent)
        XCTAssertEqual(WeekPlanner.unscheduled([open, sched, done, agent]).map(\.title), ["open"])
    }

    func test_tasksOnDay_matchesByCalendarDay() {
        let day = at("2026-06-12T00:00:00Z")
        let onDay = MustardTask(title: "on", scheduledAt: at("2026-06-12T14:00:00Z"))
        let off = MustardTask(title: "off", scheduledAt: at("2026-06-13T09:00:00Z"))
        XCTAssertEqual(WeekPlanner.tasks([onDay, off], on: day, calendar: cal).map(\.title), ["on"])
    }

    func test_scheduleDate_keepsExistingTimeOfDay() {
        let day = at("2026-06-15T00:00:00Z")
        let existing = at("2026-06-10T14:30:00Z")
        let result = WeekPlanner.scheduleDate(on: day, keepingTimeFrom: existing, calendar: cal)!
        let c = cal.dateComponents([.day, .hour, .minute], from: result)
        XCTAssertEqual(c.day, 15)
        XCTAssertEqual(c.hour, 14)
        XCTAssertEqual(c.minute, 30)
    }

    func test_scheduleDate_defaultsToNine() {
        let day = at("2026-06-15T00:00:00Z")
        let result = WeekPlanner.scheduleDate(on: day, keepingTimeFrom: nil, calendar: cal)!
        XCTAssertEqual(cal.component(.hour, from: result), 9)
    }
}
