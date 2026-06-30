import XCTest
@testable import MustardKit

/// ✦ Balance redistribution (BAK-109): greedy LPT bin-packing of movable (non-done)
/// tasks across the given weekdays to flatten the peak day. Pinned UTC.
final class WeekBalanceTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter(); f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: iso)!
    }
    // Mon–Fri 2026-06-29 … 2026-07-03
    private var weekdays: [Date] {
        ["2026-06-29", "2026-06-30", "2026-07-01", "2026-07-02", "2026-07-03"]
            .map { date("\($0)T00:00:00Z") }
    }
    private func task(_ title: String, on iso: String, est: Int, done: Bool = false) -> MustardTask {
        let t = MustardTask(title: title, scheduledAt: date(iso))
        t.estimateMinutes = est
        t.isTimed = true
        if done { t.stage = .done }
        return t
    }

    func test_balance_flattensClusteredTasks() {
        // Three 60-min tasks all stacked on Monday → spread across three days.
        let a = task("a", on: "2026-06-29T09:00:00Z", est: 60)
        let b = task("b", on: "2026-06-29T10:00:00Z", est: 60)
        let c = task("c", on: "2026-06-29T11:00:00Z", est: 60)
        let plan = WeekPlanner.balance([a, b, c], weekdays: weekdays, calendar: utc)
        XCTAssertEqual(plan.peakMinutes, 60)
        XCTAssertEqual(plan.moves.count, 2) // one stays on Monday, two move
    }

    func test_balance_alreadyBalanced_noMoves() {
        let a = task("a", on: "2026-06-29T09:00:00Z", est: 60)
        let b = task("b", on: "2026-06-30T09:00:00Z", est: 60)
        let plan = WeekPlanner.balance([a, b], weekdays: weekdays, calendar: utc)
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertEqual(plan.peakMinutes, 60)
    }

    func test_balance_excludesDoneTasks() {
        let done = task("done", on: "2026-06-29T09:00:00Z", est: 600, done: true)
        let a = task("a", on: "2026-06-29T09:00:00Z", est: 60)
        let plan = WeekPlanner.balance([done, a], weekdays: weekdays, calendar: utc)
        XCTAssertTrue(plan.moves.isEmpty) // single movable task stays put
        XCTAssertEqual(plan.peakMinutes, 60) // done's 600 not counted
    }

    func test_balance_neverRegressesPeak_returnsEmptyWhenLPTWouldWorsen() {
        // Two days, optimal layout already at peak 60 ({30,30} | {20,20,20}).
        // From-scratch greedy LPT would land on 70 — the guard must reject that and
        // leave the layout untouched.
        let twoDays = [date("2026-06-29T00:00:00Z"), date("2026-06-30T00:00:00Z")]
        let a = task("a", on: "2026-06-29T09:00:00Z", est: 30)
        let b = task("b", on: "2026-06-29T10:00:00Z", est: 30)
        let c = task("c", on: "2026-06-30T09:00:00Z", est: 20)
        let d = task("d", on: "2026-06-30T10:00:00Z", est: 20)
        let e = task("e", on: "2026-06-30T11:00:00Z", est: 20)
        let plan = WeekPlanner.balance([a, b, c, d, e], weekdays: twoDays, calendar: utc)
        XCTAssertTrue(plan.moves.isEmpty, "must not move when it can't lower the peak")
        XCTAssertEqual(plan.peakMinutes, 60, "reports the existing (un-regressed) peak")
    }

    func test_balance_excludesTasksOutsideWeekdays() {
        // A task scheduled on Saturday (outside Mon–Fri) is never moved/counted.
        let sat = MustardTask(title: "sat", scheduledAt: date("2026-07-04T09:00:00Z"))
        sat.estimateMinutes = 600; sat.isTimed = true
        let a = task("a", on: "2026-06-29T09:00:00Z", est: 60)
        let plan = WeekPlanner.balance([sat, a], weekdays: weekdays, calendar: utc)
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertEqual(plan.peakMinutes, 60) // sat's 600 not counted
    }

    func test_balance_movePreservesTimeOfDay() {
        let a = task("a", on: "2026-06-29T09:00:00Z", est: 60)
        let b = task("b", on: "2026-06-29T14:30:00Z", est: 60)
        let plan = WeekPlanner.balance([a, b], weekdays: weekdays, calendar: utc)
        // b moves to Tuesday but keeps 14:30
        let move = plan.moves.first { $0.uid == b.uid }
        XCTAssertNotNil(move)
        XCTAssertEqual(utc.component(.hour, from: move!.to), 14)
        XCTAssertEqual(utc.component(.minute, from: move!.to), 30)
    }
}
