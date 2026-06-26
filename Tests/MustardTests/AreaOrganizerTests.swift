import XCTest
@testable import MustardKit

final class AreaOrganizerTests: XCTestCase {
    private func list(_ name: String, area: Area? = nil) -> TaskList {
        TaskList(name: name, area: area)
    }
    private func task(_ title: String, list: TaskList? = nil, status: TaskStatus = .inbox,
                      created: TimeInterval = 0) -> MustardTask {
        let t = MustardTask(title: title)
        t.list = list
        t.status = status
        t.createdAt = Date(timeIntervalSince1970: created)
        return t
    }

    func test_tasks_inList_returnsOnlyThatListsTasks_anyStatus_oldestFirst() {
        let dev = list("Dev"); let ops = list("Ops")
        let a = task("a", list: dev, created: 1)
        let b = task("b", list: dev, status: .done, created: 2)
        let c = task("c", list: ops, created: 3)
        let d = task("d", created: 4) // unfiled

        let result = AreaOrganizer.tasks(in: dev, from: [b, a, c, d])
        XCTAssertEqual(result.map(\.title), ["a", "b"])
    }

    func test_unfiled_returnsOpenTasksWithNilList_oldestFirst() {
        let dev = list("Dev")
        let open2 = task("u2", created: 2)
        let open1 = task("u1", created: 1)
        let doneUnfiled = task("done", status: .done)
        let filed = task("filed", list: dev)

        let result = AreaOrganizer.unfiled([open2, open1, doneUnfiled, filed])
        XCTAssertEqual(result.map(\.title), ["u1", "u2"])
    }

    func test_openCount_forList_countsOnlyOpenFiled() {
        let dev = list("Dev")
        let tasks = [
            task("1", list: dev),
            task("2", list: dev, status: .inProgress),
            task("3", list: dev, status: .done),
            task("4", list: dev, status: .someday),
        ]
        XCTAssertEqual(AreaOrganizer.openCount(for: dev, in: tasks), 2)
    }

    func test_openCount_forArea_sumsOpenAcrossItsLists() {
        let area = Area(name: "Work")
        let dev = list("Dev", area: area); let ops = list("Ops", area: area)
        let personal = list("Personal") // no area
        let tasks = [
            task("a", list: dev), task("b", list: dev),
            task("c", list: ops),
            task("z", list: personal),
        ]
        XCTAssertEqual(AreaOrganizer.openCount(for: area, in: tasks), 3)
    }

    func test_openCount_forArea_excludesDoneAndAreaLessLists() {
        let area = Area(name: "Work")
        let dev = list("Dev", area: area)
        let orphan = list("Loose") // area == nil
        let tasks = [
            task("open", list: dev),
            task("done", list: dev, status: .done),
            task("orphan", list: orphan),
        ]
        XCTAssertEqual(AreaOrganizer.openCount(for: area, in: tasks), 1)
    }

    func test_unfiledCount_countsOpenNilListOnly() {
        let dev = list("Dev")
        let tasks = [task("u1"), task("u2", status: .done), task("f", list: dev)]
        XCTAssertEqual(AreaOrganizer.unfiledCount(tasks), 1)
    }

    func test_active_excludesDone_preservesOrder() {
        let dev = list("Dev")
        let a = task("a", list: dev, created: 1)
        let b = task("b", list: dev, status: .done, created: 2)
        let c = task("c", list: dev, status: .inProgress, created: 3)
        let d = task("d", list: dev, status: .someday, created: 4)

        let scoped = AreaOrganizer.tasks(in: dev, from: [a, b, c, d])
        XCTAssertEqual(AreaOrganizer.active(scoped).map(\.title), ["a", "c", "d"])
    }

    func test_completed_onlyDone_newestCompletionFirst() {
        let dev = list("Dev")
        let a = task("a", list: dev, created: 1)
        let oldDone = task("old", list: dev, status: .done, created: 2)
        oldDone.completedAt = Date(timeIntervalSince1970: 100)
        let newDone = task("new", list: dev, status: .done, created: 3)
        newDone.completedAt = Date(timeIntervalSince1970: 200)

        let scoped = AreaOrganizer.tasks(in: dev, from: [a, oldDone, newDone])
        XCTAssertEqual(AreaOrganizer.completed(scoped).map(\.title), ["new", "old"])
    }

    func test_sortedAreas_byNameCaseInsensitive_thenCreatedAt() {
        let zeta = Area(name: "Zeta")
        let alpha = Area(name: "alpha")
        XCTAssertEqual(AreaOrganizer.sortedAreas([zeta, alpha]).map(\.name), ["alpha", "Zeta"])

        let first = Area(name: "Same"); first.createdAt = Date(timeIntervalSince1970: 1)
        let second = Area(name: "same"); second.createdAt = Date(timeIntervalSince1970: 2)
        XCTAssertEqual(
            AreaOrganizer.sortedAreas([second, first]).map(\.createdAt),
            [first.createdAt, second.createdAt]
        )
    }

    func test_sortedLists_byNameCaseInsensitive() {
        let beta = list("beta"); let alpha = list("Alpha")
        XCTAssertEqual(AreaOrganizer.sortedLists([beta, alpha]).map(\.name), ["Alpha", "beta"])
    }

    func test_areaLessLists_returnsOnlyNilAreaLists_sorted() {
        let area = Area(name: "Work")
        let filed = list("Dev", area: area)
        let looseZ = list("Zeta"); let looseA = list("alpha")
        let result = AreaOrganizer.areaLessLists([filed, looseZ, looseA])
        XCTAssertEqual(result.map(\.name), ["alpha", "Zeta"])
    }
}
