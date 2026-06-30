import XCTest
@testable import MustardKit

/// Week capacity, load tiers, and time-of-day grouping (BAK-105). Pinned UTC.
final class WeekCapacityTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter(); f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: iso)!
    }
    private func task(_ title: String, at iso: String, est: Int = 30, timed: Bool = true, done: Bool = false) -> MustardTask {
        let t = MustardTask(title: title, scheduledAt: date(iso))
        t.estimateMinutes = est
        t.isTimed = timed
        if done { t.stage = .done }
        return t
    }

    // MARK: capacity

    func test_capacityMinutes_sumsNonDoneForThatDay() {
        let day = date("2026-07-01T00:00:00Z")
        let a = task("a", at: "2026-07-01T09:00:00Z", est: 60)
        let b = task("b", at: "2026-07-01T11:00:00Z", est: 90)
        let doneOne = task("done", at: "2026-07-01T13:00:00Z", est: 120, done: true)
        let otherDay = task("x", at: "2026-07-02T09:00:00Z", est: 200)
        let mins = WeekPlanner.capacityMinutes([a, b, doneOne, otherDay], on: day, calendar: utc)
        XCTAssertEqual(mins, 150) // 60 + 90; done + other-day excluded
    }

    // MARK: load tier

    func test_loadTier_boundaries() {
        XCTAssertEqual(WeekPlanner.loadTier(minutes: 0), .green)
        XCTAssertEqual(WeekPlanner.loadTier(minutes: 360), .green)
        XCTAssertEqual(WeekPlanner.loadTier(minutes: 361), .amber)
        XCTAssertEqual(WeekPlanner.loadTier(minutes: 480), .amber)
        XCTAssertEqual(WeekPlanner.loadTier(minutes: 481), .red)
    }

    // MARK: capacity label

    func test_capacityLabel() {
        XCTAssertEqual(WeekPlanner.capacityLabel(minutes: 0), "—")
        XCTAssertEqual(WeekPlanner.capacityLabel(minutes: 45), "45m")
        XCTAssertEqual(WeekPlanner.capacityLabel(minutes: 60), "1h")
        XCTAssertEqual(WeekPlanner.capacityLabel(minutes: 90), "1.5h")
        XCTAssertEqual(WeekPlanner.capacityLabel(minutes: 210), "3.5h")
    }

    // MARK: time-of-day

    func test_timeOfDay_buckets() {
        XCTAssertEqual(WeekPlanner.timeOfDay(for: date("2026-07-01T09:00:00Z"), calendar: utc), .morning)
        XCTAssertEqual(WeekPlanner.timeOfDay(for: date("2026-07-01T12:00:00Z"), calendar: utc), .afternoon)
        XCTAssertEqual(WeekPlanner.timeOfDay(for: date("2026-07-01T16:59:00Z"), calendar: utc), .afternoon)
        XCTAssertEqual(WeekPlanner.timeOfDay(for: date("2026-07-01T17:00:00Z"), calendar: utc), .evening)
    }

    func test_groupByTimeOfDay_ordersAndOmitsEmpty_untimedIsAnytime() {
        let morning = task("m", at: "2026-07-01T09:00:00Z")
        let evening = task("e", at: "2026-07-01T18:00:00Z")
        let anytime = task("any", at: "2026-07-01T09:00:00Z", timed: false)
        let groups = WeekPlanner.groupByTimeOfDay([evening, anytime, morning], calendar: utc)
        XCTAssertEqual(groups.map { $0.0 }, [.morning, .evening, .anytime]) // afternoon omitted, ordered
        XCTAssertEqual(groups.first?.1.first?.title, "m")
    }
}
