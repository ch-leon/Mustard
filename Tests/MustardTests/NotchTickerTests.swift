import XCTest
@testable import MustardKit

final class NotchTickerTests: XCTestCase {
    func test_idleItems_withFocusAndWaiting_rotatesBoth() {
        let items = NotchTicker.idleItems(focusTitle: "Draft release notes", waitingCount: 3)
        XCTAssertEqual(items, ["Draft release notes", "3 waiting"])
    }

    func test_idleItems_focusOnly() {
        XCTAssertEqual(
            NotchTicker.idleItems(focusTitle: "Standup", waitingCount: 0),
            ["Standup"]
        )
    }

    func test_idleItems_waitingOnly_singular() {
        XCTAssertEqual(
            NotchTicker.idleItems(focusTitle: nil, waitingCount: 1),
            ["1 waiting"]
        )
    }

    func test_idleItems_neither_fallsBackToCalm() {
        XCTAssertEqual(
            NotchTicker.idleItems(focusTitle: nil, waitingCount: 0),
            ["All clear"]
        )
    }

    func test_idleItems_includesNextEventBetweenFocusAndWaiting() {
        let items = NotchTicker.idleItems(
            focusTitle: "Write notes", waitingCount: 2, nextEvent: "Standup 9:30"
        )
        XCTAssertEqual(items, ["Write notes", "Standup 9:30", "2 waiting"])
    }

    func test_idleItems_nextEventOnly() {
        XCTAssertEqual(
            NotchTicker.idleItems(focusTitle: nil, waitingCount: 0, nextEvent: "Standup 9:30"),
            ["Standup 9:30"]
        )
    }

    func test_idleItems_planPromptLeadsRotation() {
        let items = NotchTicker.idleItems(focusTitle: "Deep work", waitingCount: 2, planPrompt: true)
        XCTAssertEqual(items.first, "Plan your day ✦")
        XCTAssertTrue(items.contains("Deep work"))
    }

    func test_idleItems_noPlanPrompt_unchanged() {
        XCTAssertEqual(NotchTicker.idleItems(focusTitle: nil, waitingCount: 0, planPrompt: false), ["All clear"])
    }

    func test_idleItems_planPromptAlone_leadsWithoutAllClear() {
        XCTAssertEqual(
            NotchTicker.idleItems(focusTitle: nil, waitingCount: 0, planPrompt: true),
            ["Plan your day ✦"]
        )
    }

    func test_item_cyclesByIndex() {
        let items = ["a", "b", "c"]
        XCTAssertEqual(NotchTicker.item(items, tick: 0), "a")
        XCTAssertEqual(NotchTicker.item(items, tick: 4), "b")
        XCTAssertEqual(NotchTicker.item(items, tick: 5), "c")
        XCTAssertEqual(NotchTicker.item([], tick: 9), "")
    }
}
