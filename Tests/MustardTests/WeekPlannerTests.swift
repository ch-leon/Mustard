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

    func test_unscheduled_excludesSubtasks() {
        // Subtasks (tasks with a parent) belong to their parent, not the top-level rail.
        let parent = MustardTask(title: "parent")
        let sub = MustardTask(title: "sub"); sub.parent = parent
        XCTAssertEqual(WeekPlanner.unscheduled([parent, sub]).map(\.title), ["parent"])
    }

    func test_overdue_excludesSubtasks() {
        let now = at("2026-06-12T12:00:00Z")
        let parent = MustardTask(title: "parent", scheduledAt: at("2026-06-10T09:00:00Z"))
        let sub = MustardTask(title: "sub", scheduledAt: at("2026-06-10T09:00:00Z")); sub.parent = parent
        XCTAssertEqual(WeekPlanner.overdue([parent, sub], now: now, calendar: cal).map(\.title), ["parent"])
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

    // MARK: - Axis overlap columns

    private func span(_ id: String, _ start: Int, _ end: Int) -> WeekPlanner.AxisSpan {
        WeekPlanner.AxisSpan(id: id, startMinute: start, endMinute: end)
    }

    func test_axisColumns_nonOverlapping_allSingleColumn() {
        let cols = WeekPlanner.axisColumns([span("a", 0, 30), span("b", 60, 90)])
        XCTAssertEqual(cols["a"], .init(column: 0, columnCount: 1))
        XCTAssertEqual(cols["b"], .init(column: 0, columnCount: 1))
    }

    func test_axisColumns_sameTime_splitsSideBySide() {
        let cols = WeekPlanner.axisColumns([span("a", 60, 120), span("b", 60, 120)])
        XCTAssertEqual(cols["a"]?.columnCount, 2)
        XCTAssertEqual(cols["b"]?.columnCount, 2)
        XCTAssertEqual(Set([cols["a"]!.column, cols["b"]!.column]), [0, 1])
    }

    func test_axisColumns_threeConcurrent_threeColumns() {
        let cols = WeekPlanner.axisColumns([span("a", 0, 60), span("b", 0, 60), span("c", 0, 60)])
        XCTAssertEqual(Set([cols["a"]!.column, cols["b"]!.column, cols["c"]!.column]), [0, 1, 2])
        XCTAssertTrue([cols["a"], cols["b"], cols["c"]].allSatisfy { $0?.columnCount == 3 })
    }

    func test_axisColumns_chain_reusesFreedColumn() {
        // a[0-30] b[20-50] c[40-70]: a&b overlap, b&c overlap, a&c don't.
        // c can reuse a's column → cluster width 2.
        let cols = WeekPlanner.axisColumns([span("a", 0, 30), span("b", 20, 50), span("c", 40, 70)])
        XCTAssertEqual(cols["a"], .init(column: 0, columnCount: 2))
        XCTAssertEqual(cols["b"], .init(column: 1, columnCount: 2))
        XCTAssertEqual(cols["c"], .init(column: 0, columnCount: 2))
    }

    func test_axisColumns_separateClusters_resetColumnCount() {
        // a&b overlap (cluster 1, width 2); c alone (cluster 2, width 1).
        let cols = WeekPlanner.axisColumns([span("a", 0, 60), span("b", 30, 90), span("c", 120, 150)])
        XCTAssertEqual(cols["a"]?.columnCount, 2)
        XCTAssertEqual(cols["b"]?.columnCount, 2)
        XCTAssertEqual(cols["c"], .init(column: 0, columnCount: 1))
    }
}
