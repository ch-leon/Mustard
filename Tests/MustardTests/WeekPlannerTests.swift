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
        XCTAssertEqual(
            WeekPlanner.tasks([onDay, off], on: day, now: at("2026-06-12T00:00:00Z"), calendar: cal).map(\.title),
            ["on"])
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

    // MARK: - Overdue (rail re-planning queue)

    func test_overdue_isOpenMyTasksBeforeToday() {
        let now = at("2026-06-14T10:00:00Z")
        let past = MustardTask(title: "past", scheduledAt: at("2026-06-12T09:00:00Z"))
        let earlier = MustardTask(title: "earlier", scheduledAt: at("2026-06-10T09:00:00Z"))
        let today = MustardTask(title: "today", scheduledAt: at("2026-06-14T09:00:00Z"))
        let future = MustardTask(title: "future", scheduledAt: at("2026-06-16T09:00:00Z"))
        let donePast = MustardTask(title: "donePast", scheduledAt: at("2026-06-11T09:00:00Z")); donePast.markDone()
        let agentPast = MustardTask(title: "agentPast", owner: .agent, scheduledAt: at("2026-06-11T09:00:00Z"))
        let unscheduled = MustardTask(title: "unsched")
        let result = WeekPlanner.overdue(
            [past, earlier, today, future, donePast, agentPast, unscheduled], now: now, calendar: cal)
        // Open, mine, strictly before today's start — oldest first.
        XCTAssertEqual(result.map(\.title), ["earlier", "past"])
    }

    func test_tasksOnDay_excludesOverdueOpenMyTasks() {
        let now = at("2026-06-14T10:00:00Z")
        let pastDay = at("2026-06-12T00:00:00Z")
        let overdueOpen = MustardTask(title: "overdueOpen", scheduledAt: at("2026-06-12T14:00:00Z"))
        let donePast = MustardTask(title: "donePast", scheduledAt: at("2026-06-12T14:00:00Z")); donePast.markDone()
        let agentPast = MustardTask(title: "agentPast", owner: .agent, scheduledAt: at("2026-06-12T14:00:00Z"))
        let onPastDay = WeekPlanner.tasks(
            [overdueOpen, donePast, agentPast], on: pastDay, now: now, calendar: cal)
        // Overdue open *my* task is pulled to the rail; done + agent stay on their day.
        XCTAssertEqual(Set(onPastDay.map(\.title)), ["donePast", "agentPast"])
    }

    func test_tasksOnDay_keepsTodayAndFutureOpenTasks() {
        let now = at("2026-06-14T10:00:00Z")
        let todayDay = at("2026-06-14T00:00:00Z")
        let todayOpen = MustardTask(title: "todayOpen", scheduledAt: at("2026-06-14T14:00:00Z"))
        XCTAssertEqual(
            WeekPlanner.tasks([todayOpen], on: todayDay, now: now, calendar: cal).map(\.title),
            ["todayOpen"])
    }

    // MARK: - Resize / axis math

    func test_snapDuration_snapsToThirtyWithFloor() {
        XCTAssertEqual(WeekPlanner.snapDuration(7), 30)    // below floor → floor
        XCTAssertEqual(WeekPlanner.snapDuration(44), 30)   // rounds to nearest 30
        XCTAssertEqual(WeekPlanner.snapDuration(46), 60)
        XCTAssertEqual(WeekPlanner.snapDuration(75), 90)
    }

    func test_minutesSinceDayStart_fromAxisStart() {
        let nineThirty = at("2026-06-14T09:30:00Z")
        XCTAssertEqual(
            WeekPlanner.minutesSinceDayStart(nineThirty, dayStartHour: 8, calendar: cal), 90)
        let sevenAM = at("2026-06-14T07:00:00Z")
        XCTAssertEqual(
            WeekPlanner.minutesSinceDayStart(sevenAM, dayStartHour: 8, calendar: cal), -60)
    }
}
