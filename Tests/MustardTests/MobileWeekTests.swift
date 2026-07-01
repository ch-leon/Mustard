import XCTest
@testable import MustardKit

/// Mobile Week (BAK-116) reuses the board's tested area predicate to scope the
/// day-strip capacity, the rail, and the selected-day list to the shared area
/// filter. This pins that public predicate — the only new pure logic the screen
/// adds; day-strip / capacity / scheduling all compose existing WeekPlanner funcs.
final class MobileWeekTests: XCTestCase {
    private func task(_ title: String, area name: String?) -> MustardTask {
        let t = MustardTask(title: title)
        if let name {
            let a = Area(name: name, colorHex: "#2D7FF9")
            t.list = TaskList(name: name, area: a)
        }
        return t
    }

    func test_matchesArea_all_matchesEverything() {
        XCTAssertTrue(PersonalBoard.matchesArea(task("x", area: "DLA SDK"), .all))
        XCTAssertTrue(PersonalBoard.matchesArea(task("y", area: nil), .all))
    }

    func test_matchesArea_namedArea_matchesOnlyThatArea() {
        XCTAssertTrue(PersonalBoard.matchesArea(task("x", area: "DLA SDK"), .area("DLA SDK")))
        XCTAssertFalse(PersonalBoard.matchesArea(task("y", area: "Admin"), .area("DLA SDK")))
        XCTAssertFalse(PersonalBoard.matchesArea(task("z", area: nil), .area("DLA SDK")))
    }

    func test_matchesArea_personal_matchesErrandsAndReading() {
        XCTAssertTrue(PersonalBoard.matchesArea(task("x", area: "Errands"), .personal))
        XCTAssertTrue(PersonalBoard.matchesArea(task("y", area: "Reading"), .personal))
        XCTAssertFalse(PersonalBoard.matchesArea(task("z", area: "DLA SDK"), .personal))
    }
}
