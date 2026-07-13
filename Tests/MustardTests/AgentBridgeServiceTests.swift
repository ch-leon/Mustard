import XCTest
import SwiftData
@testable import MustardKit

final class AgentBridgeServiceTests: XCTestCase {
    final class StubIO: BridgeIO {
        var written: [AgentWorkOrder] = []
        var cancelled: [String] = []
        var archived: [String] = []
        var live: Set<String> = []
        var liveResults: Set<String> = []
        var results: [(AgentResult, String)] = []
        var quarantineCalls = 0
        func liveOutboxUIDs(workingDir: String) -> Set<String> { live }
        func liveResultUIDs(workingDir: String) -> Set<String> { liveResults }
        func writeWorkOrder(_ order: AgentWorkOrder, workingDir: String) throws { written.append(order) }
        func cancelWorkOrder(uid: String, workingDir: String) throws { cancelled.append(uid) }
        func readResults(workingDir: String) -> [(result: AgentResult, path: String)] { results.map { ($0.0, $0.1) } }
        func archiveResult(_ path: String, workingDir: String) throws { archived.append(path) }
        func quarantineUndecodableResults(workingDir: String) -> Int { quarantineCalls += 1; return 0 }
    }

    @MainActor
    private func service(_ io: StubIO) throws -> (AgentService, ModelContext) {
        let c = try ModelContainer(for: Area.self, TaskList.self, MustardTask.self, Recommendation.self,
                                   AgentRun.self, AgentMessage.self, CalendarEvent.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        return (AgentService(context: ctx, claude: { _, _ in .init(ok: true, text: "") }, bridge: io), ctx)
    }

    @MainActor
    func test_export_skipsOrdinaryQueuedLocalTask() throws {
        let io = StubIO(); let (svc, ctx) = try service(io)
        // Route the task to the DL area so exportWorkOrders' area filter selects it.
        let area = Area(name: "Digital Licence")
        let list = TaskList(name: "DL", area: area)
        let t = MustardTask(title: "ship"); t.uid = "u1"; t.stage = .queued; t.actionType = .ticket
        t.list = list
        ctx.insert(area); ctx.insert(list); ctx.insert(t)
        svc.exportWorkOrders(workingDir: "/kb/DL", area: "Digital Licence", project: "DL")
        XCTAssertTrue(io.written.isEmpty)
    }

    @MainActor
    func test_export_writesConnectedFallbackTask() throws {
        let io = StubIO(); let (svc, ctx) = try service(io)
        let area = Area(name: "Digital Licence")
        let list = TaskList(name: "DL", area: area)
        let t = MustardTask(title: "ship"); t.uid = "u1"; t.stage = .queued; t.actionType = .ticket
        t.list = list
        let run = AgentRun(task: t)
        run.requiresConnectedWorker = true
        t.agentRun = run
        ctx.insert(area); ctx.insert(list); ctx.insert(t); ctx.insert(run)

        svc.exportWorkOrders(workingDir: "/kb/DL", area: "Digital Licence", project: "DL")

        XCTAssertEqual(io.written.map(\.uid), ["u1"])
        XCTAssertEqual(io.written.first?.mode, "execute")
    }

    // BAK-92 regression: a queued task whose result is written but NOT yet ingested
    // (outbox already archived, so no live outbox) must not be re-exported — otherwise
    // the worker runs it twice (e.g. a second Gmail draft / Shortcut story).
    @MainActor
    func test_export_skipsQueuedTask_whenLiveResultPending() throws {
        let io = StubIO(); let (svc, ctx) = try service(io)
        let area = Area(name: "Digital Licence")
        let list = TaskList(name: "DL", area: area)
        let t = MustardTask(title: "ship"); t.uid = "u1"; t.stage = .queued; t.actionType = .ticket
        t.list = list
        let run = AgentRun(task: t)
        run.requiresConnectedWorker = true
        t.agentRun = run
        ctx.insert(area); ctx.insert(list); ctx.insert(t); ctx.insert(run)
        io.live = []                 // worker already archived the outbox
        io.liveResults = ["u1"]      // result written, not yet ingested
        svc.exportWorkOrders(workingDir: "/kb/DL", area: "Digital Licence", project: "DL")
        XCTAssertTrue(io.written.isEmpty, "must not re-issue a duplicate while a result is pending ingest")
    }

    @MainActor
    func test_ingest_appliesExecuteResult_andArchives() throws {
        let io = StubIO(); let (svc, ctx) = try service(io)
        let t = MustardTask(title: "ship"); t.uid = "u1"; t.stage = .queued
        ctx.insert(t)
        io.results = [(AgentResult(uid: "u1", mode: "execute", status: "done", actionType: nil,
            title: nil, body: nil, links: [TaskLink(label: "SC", url: "https://x")], summary: "done", error: nil),
            "/kb/DL/_agent/results/u1.json")]
        svc.ingestAgentResults(workingDir: "/kb/DL")
        XCTAssertEqual(t.stage, .needsReview)
        XCTAssertEqual(t.links.first?.url, "https://x")
        XCTAssertEqual(io.archived.count, 1)
    }

    // BAK-84: ingest sweeps undecodable result files aside each run.
    @MainActor
    func test_ingest_quarantinesUndecodableResults() throws {
        let io = StubIO(); let (svc, _) = try service(io)
        svc.ingestAgentResults(workingDir: "/kb/DL")
        XCTAssertEqual(io.quarantineCalls, 1)
    }
}
