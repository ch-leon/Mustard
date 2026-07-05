import XCTest
@testable import MustardKit

final class RitualPlannerTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private let day = Date(timeIntervalSince1970: 1_751_760_000)

    private func task(_ title: String, scheduled: Date? = nil) -> MustardTask {
        MustardTask(title: title, scheduledAt: scheduled)
    }

    func test_rollover_onlyOpenTasksStampedToday() {
        let rolled = task("rolled", scheduled: day); rolled.carriedForwardAt = day
        let oldStamp = task("old", scheduled: day); oldStamp.carriedForwardAt = day.addingTimeInterval(-86_400)
        let done = task("done", scheduled: day); done.carriedForwardAt = day; done.stage = .done
        let fresh = task("fresh", scheduled: day)
        XCTAssertEqual(RitualPlanner.rollover([rolled, oldStamp, done, fresh], day: day, calendar: cal).map(\.title), ["rolled"])
    }

    func test_pushToTomorrow_keepsTimeOfDay() {
        let t = task("x", scheduled: day.addingTimeInterval(9 * 3_600))   // 09:00
        RitualPlanner.pushToTomorrow(t, calendar: cal)
        XCTAssertEqual(t.scheduledAt, day.addingTimeInterval(86_400 + 9 * 3_600))
    }

    func test_sendToInbox_clearsSchedule() {
        let t = task("x", scheduled: day)
        RitualPlanner.sendToInbox(t)
        XCTAssertNil(t.scheduledAt)
    }

    func test_pickCandidates_unscheduledOpenMineOnly() {
        let inboxTask = task("pick me")
        let scheduled = task("planned", scheduled: day)
        let done = task("done"); done.stage = .done
        let agents = task("agent's"); agents.owner = .agent
        XCTAssertEqual(RitualPlanner.pickCandidates([inboxTask, scheduled, done, agents]).map(\.title), ["pick me"])
    }

    func test_planToday_setsUntimedToday() {
        let t = task("x")
        RitualPlanner.planToday(t, day: day.addingTimeInterval(13 * 3_600), calendar: cal)
        XCTAssertNotNil(t.scheduledAt)
        XCTAssertTrue(cal.isDate(t.scheduledAt!, inSameDayAs: day))
        XCTAssertFalse(t.isTimed)
    }

    func test_capacityLine_nilWhenNothingPlanned_labelOtherwise() {
        XCTAssertNil(RitualPlanner.capacityLine([task("loose")], day: day, calendar: cal))
        let planned = task("a", scheduled: day)          // default estimate 30m
        XCTAssertEqual(RitualPlanner.capacityLine([planned], day: day, calendar: cal), "30m planned")
    }

    func test_focus_toggleCapsAtThree() {
        let ts = (0..<4).map { i in task("t\(i)", scheduled: day) }
        for t in ts.prefix(3) { XCTAssertTrue(RitualPlanner.toggleFocus(t, in: ts, day: day, calendar: cal)) }
        XCTAssertFalse(RitualPlanner.toggleFocus(ts[3], in: ts, day: day, calendar: cal))   // 4th refused
        XCTAssertEqual(RitualPlanner.focused(ts, day: day, calendar: cal).count, 3)
        XCTAssertTrue(RitualPlanner.toggleFocus(ts[0], in: ts, day: day, calendar: cal))    // un-star works
        XCTAssertEqual(RitualPlanner.focused(ts, day: day, calendar: cal).count, 2)
    }

    func test_focus_doneStarFreesASlot() {
        let ts = (0..<4).map { i in task("t\(i)", scheduled: day) }
        for t in ts.prefix(3) { XCTAssertTrue(RitualPlanner.toggleFocus(t, in: ts, day: day, calendar: cal)) }
        ts[0].stage = .done                                     // completed star keeps its focusOnDay
        XCTAssertTrue(RitualPlanner.toggleFocus(ts[3], in: ts, day: day, calendar: cal))   // slot freed
        XCTAssertEqual(RitualPlanner.focused(ts, day: day, calendar: cal).count, 4)        // done star still shows
        XCTAssertEqual(RitualPlanner.focused(ts, day: day, calendar: cal).filter { $0.stage.isOpen }.count, 3)
    }

    func test_focusTitle_firstOpenBySchedule_nilWhenNone() {
        let a = task("later", scheduled: day.addingTimeInterval(10 * 3_600)); a.focusOnDay = day
        let b = task("earlier", scheduled: day.addingTimeInterval(8 * 3_600)); b.focusOnDay = day
        let doneFocus = task("done", scheduled: day); doneFocus.focusOnDay = day; doneFocus.stage = .done
        XCTAssertEqual(RitualPlanner.focusTitle([a, b, doneFocus], day: day, calendar: cal), "earlier")
        XCTAssertNil(RitualPlanner.focusTitle([doneFocus], day: day, calendar: cal))
    }
}
