import XCTest
import SwiftData
@testable import MustardKit

final class ModelTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, Recommendation.self, OutputCard.self, CalendarEvent.self, configurations: config
        )
        return ModelContext(container)
    }

    func test_newTask_defaultsToInboxOwnedByMe() throws {
        let task = MustardTask(title: "Draft notes")
        XCTAssertEqual(task.status, .inbox)
        XCTAssertEqual(task.owner, .me)
        XCTAssertNil(task.scheduledAt)
    }

    func test_markDone_setsStatusAndCompletedAt() throws {
        let task = MustardTask(title: "x")
        let when = Date(timeIntervalSince1970: 1_000_000)
        task.markDone(now: when)
        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(task.completedAt, when)
    }

    func test_insertAndFetch_roundTrips() throws {
        let ctx = try makeContext()
        ctx.insert(MustardTask(title: "Persisted"))
        let fetched = try ctx.fetch(FetchDescriptor<MustardTask>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Persisted")
    }

    func test_statusAccessor_survivesRawRoundTrip() throws {
        let task = MustardTask(title: "x")
        task.status = .inProgress
        XCTAssertEqual(task.statusRaw, "inProgress")
        XCTAssertEqual(task.status, .inProgress)
    }

    func test_deletingList_keepsTasks_unfilesThem() throws {
        let ctx = try makeContext()
        let area = Area(name: "Work")
        let list = TaskList(name: "Dev", area: area)
        let task = MustardTask(title: "Filed")
        task.list = list
        ctx.insert(area); ctx.insert(list); ctx.insert(task)
        try ctx.save()

        ctx.delete(list)
        try ctx.save()

        let tasks = try ctx.fetch(FetchDescriptor<MustardTask>())
        XCTAssertEqual(tasks.count, 1, "task should survive its list's deletion")
        XCTAssertNil(tasks.first?.list, "task should be unfiled, not deleted")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<TaskList>()).count, 0)
    }

    func test_deletingArea_keepsLists_orphansThem() throws {
        let ctx = try makeContext()
        let area = Area(name: "Work")
        let list = TaskList(name: "Dev", area: area)
        ctx.insert(area); ctx.insert(list)
        try ctx.save()

        ctx.delete(area)
        try ctx.save()

        let lists = try ctx.fetch(FetchDescriptor<TaskList>())
        XCTAssertEqual(lists.count, 1, "list should survive its area's deletion")
        XCTAssertNil(lists.first?.area, "list should be area-less, not deleted")
    }
}
