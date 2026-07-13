import XCTest
@testable import MustardKit

final class AgentTaskQueueTests: XCTestCase {
    func test_nextRunnablePrioritizesPriorityBeforeAge() {
        let adjacentPriorities: [(higher: TaskPriority, lower: TaskPriority)] = [
            (.urgent, .high),
            (.high, .normal),
            (.normal, .low),
        ]

        for (higher, lower) in adjacentPriorities {
            let oldLower = makeTask(
                uid: "old-\(lower.rawValue)",
                priority: lower,
                createdAt: date(100)
            )
            let newHigher = makeTask(
                uid: "new-\(higher.rawValue)",
                priority: higher,
                createdAt: date(200)
            )

            XCTAssertTrue(AgentTaskQueue.nextRunnable(from: [oldLower, newHigher]) === newHigher)
        }
    }

    func test_nextRunnableUsesOldestCreationDateWithinPriority() {
        let newer = makeTask(uid: "newer", priority: .high, createdAt: date(200))
        let older = makeTask(uid: "older", priority: .high, createdAt: date(100))

        XCTAssertTrue(AgentTaskQueue.nextRunnable(from: [newer, older]) === older)
    }

    func test_nextRunnableSkipsNonRunnableStagesWrongOwnerAndBlockedTasks() {
        let needsInput = makeTask(uid: "needs-input", stage: .needsInput)
        let inProgress = makeTask(uid: "in-progress", stage: .inProgress)
        let needsReview = makeTask(uid: "needs-review", stage: .needsReview)
        let wrongOwner = makeTask(uid: "wrong-owner", owner: .me)
        let blocked = makeTask(uid: "blocked")
        blocked.blockedReason = "Waiting on approval"

        XCTAssertNil(AgentTaskQueue.nextRunnable(from: [
            needsInput, inProgress, needsReview, wrongOwner, blocked,
        ]))
    }

    func test_nextRunnableAcceptsForAgentAndQueuedStages() {
        let queued = makeTask(uid: "queued", stage: .queued, createdAt: date(200))
        let forAgent = makeTask(uid: "for-agent", stage: .forAgent, createdAt: date(100))

        XCTAssertTrue(AgentTaskQueue.nextRunnable(from: [queued, forAgent]) === forAgent)
    }

    func test_nextRunnableDeterministicallyBreaksExactTiesByUID() {
        let z = makeTask(uid: "task-z", createdAt: date(100))
        let a = makeTask(uid: "task-a", createdAt: date(100))

        XCTAssertTrue(AgentTaskQueue.nextRunnable(from: [z, a]) === a)
        XCTAssertTrue(AgentTaskQueue.nextRunnable(from: [a, z]) === a)
    }

    func test_routeMapsTaskAreaToEnabledSource() {
        let task = makeTask(areaName: "Digital Licence")
        let settings = SourceSettings(
            sources: [
                SourceConfig(
                    id: .vault,
                    project: "DL-Knowledge-Base",
                    enabled: true,
                    workingDirectory: "/kb/DL"
                ),
            ],
            state: []
        )

        XCTAssertEqual(
            AgentTaskQueue.route(task, settings: settings),
            AgentTaskRoute(project: "DL-Knowledge-Base", workingDirectory: "/kb/DL")
        )
    }

    func test_routeReturnsNilWithoutListOrArea() {
        let noList = makeTask()
        let noArea = makeTask()
        noArea.list = TaskList(name: "Unfiled")
        let settings = settings(project: "DL-Knowledge-Base", workingDirectory: "/kb/DL")

        XCTAssertNil(AgentTaskQueue.route(noList, settings: settings))
        XCTAssertNil(AgentTaskQueue.route(noArea, settings: settings))
    }

    func test_routeReturnsNilWhenNoProjectMapsToArea() {
        let task = makeTask(areaName: "Digital Licence")
        let settings = settings(project: "Unknown", workingDirectory: "/kb/unknown")

        XCTAssertNil(AgentTaskQueue.route(task, settings: settings))
    }

    func test_routeReturnsNilForDisabledSource() {
        let task = makeTask(areaName: "Digital Licence")
        let settings = SourceSettings(
            sources: [
                SourceConfig(
                    id: .vault,
                    project: "DL-Knowledge-Base",
                    enabled: false,
                    workingDirectory: "/kb/DL"
                ),
            ],
            state: []
        )

        XCTAssertNil(AgentTaskQueue.route(task, settings: settings))
    }

    func test_routeReturnsNilForEmptyOrWhitespaceWorkingDirectory() {
        let task = makeTask(areaName: "Digital Licence")

        XCTAssertNil(AgentTaskQueue.route(
            task,
            settings: settings(project: "DL-Knowledge-Base", workingDirectory: "")
        ))
        XCTAssertNil(AgentTaskQueue.route(
            task,
            settings: settings(project: "DL-Knowledge-Base", workingDirectory: "  \n\t")
        ))
    }

    func test_routeUsesFirstMatchingSourceInSettingsOrder() {
        let task = makeTask(areaName: "Digital Licence")
        let settings = SourceSettings(
            sources: [
                SourceConfig(id: .vault, project: "DL", workingDirectory: "/kb/first"),
                SourceConfig(
                    id: .vault,
                    project: "DL-Knowledge-Base",
                    workingDirectory: "/kb/second"
                ),
            ],
            state: []
        )

        XCTAssertEqual(
            AgentTaskQueue.route(task, settings: settings),
            AgentTaskRoute(project: "DL", workingDirectory: "/kb/first")
        )
    }

    private func makeTask(
        uid: String = UUID().uuidString,
        owner: TaskOwner = .agent,
        stage: TaskStage = .forAgent,
        priority: TaskPriority = .normal,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        areaName: String? = nil
    ) -> MustardTask {
        let task = MustardTask(title: uid, owner: owner)
        task.uid = uid
        task.stage = stage
        task.priority = priority
        task.createdAt = createdAt
        if let areaName {
            task.list = TaskList(name: "Work", area: Area(name: areaName))
        }
        return task
    }

    private func settings(project: String, workingDirectory: String) -> SourceSettings {
        SourceSettings(
            sources: [
                SourceConfig(
                    id: .vault,
                    project: project,
                    enabled: true,
                    workingDirectory: workingDirectory
                ),
            ],
            state: []
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
