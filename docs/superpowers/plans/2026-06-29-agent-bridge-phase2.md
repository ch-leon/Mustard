# Agent Bridge (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Mustard's two halves of the agent bridge — export `forAgent`/`queued` board tasks to per-KB vault files, and ingest result files back into `needsApproval`/`needsReview` — plus the documented file contract.

**Architecture:** Pure planners (`BridgeExport`, `BridgeIngest`) over board state + an injected `BridgeIO` (FileManager) wrapper, orchestrated by two thin `AgentService` methods wired into the existing ~10-min loop. Mirrors the `_recs/` → `InboxIngest` precedent (JSON files, ISO-8601, `AreaRouter` routing). Archive-on-consume + a stale-stage guard give idempotency.

**Tech Stack:** Swift Package, SwiftData, XCTest. Logic is TDD; loop wiring verified by `swift build`.

**Spec:** `docs/specs/2026-06-29-agent-bridge-phase2-design.md`

---

## File structure

**Create:**
- `Sources/MustardKit/Logic/BridgeProtocol.swift` — `AgentWorkOrder`, `AgentResult` (Codable) + folder-name constants. (`TaskLink` already exists in `TaskStage.swift`.)
- `Sources/MustardKit/Logic/BridgeExport.swift` — pure: which work orders to write, which stale ones to cancel.
- `Sources/MustardKit/Logic/BridgeIngest.swift` — pure: apply a result to its task under the stage guard.
- `Sources/MustardKit/Agent/BridgeIO.swift` — `BridgeIO` protocol + `FileBridgeIO` (FileManager) impl.
- Tests: `BridgeProtocolTests`, `BridgeExportTests`, `BridgeIngestTests`, `FileBridgeIOTests`, `AgentBridgeServiceTests`.

**Modify:**
- `Sources/MustardKit/Agent/AgentService.swift` — add `exportWorkOrders(_:)` + `ingestAgentResults(_:)`.
- `Sources/Mustard/MustardApp.swift` — call both in the ~10-min loop block.

---

## Task 1: Bridge schemas + folder constants

**Files:**
- Create: `Sources/MustardKit/Logic/BridgeProtocol.swift`
- Test: `Tests/MustardTests/BridgeProtocolTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MustardKit

final class BridgeProtocolTests: XCTestCase {
    func test_workOrder_roundTrips() throws {
        let o = AgentWorkOrder(
            uid: "u1", mode: "execute", actionType: "ticket_write", title: "T", body: "B",
            area: "Digital Licence", project: "DL", sourceContext: "ctx",
            links: [TaskLink(label: "Jira", url: "https://x")], createdAt: Date(timeIntervalSince1970: 1))
        let data = try BridgeCoding.encoder.encode(o)
        let back = try BridgeCoding.decoder.decode(AgentWorkOrder.self, from: data)
        XCTAssertEqual(o, back)
    }

    func test_result_decodes_withMissingOptionals() throws {
        let json = #"{"uid":"u1","mode":"execute","status":"done"}"#.data(using: .utf8)!
        let r = try BridgeCoding.decoder.decode(AgentResult.self, from: json)
        XCTAssertEqual(r.uid, "u1"); XCTAssertEqual(r.status, "done")
        XCTAssertNil(r.links); XCTAssertNil(r.error)
    }

    func test_folderConstants() {
        XCTAssertEqual(BridgeFolders.outbox, "_agent/outbox")
        XCTAssertEqual(BridgeFolders.outboxDone, "_agent/outbox/done")
        XCTAssertEqual(BridgeFolders.results, "_agent/results")
        XCTAssertEqual(BridgeFolders.resultsDone, "_agent/results/done")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter BridgeProtocolTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum BridgeFolders {
    public static let outbox = "_agent/outbox"
    public static let outboxDone = "_agent/outbox/done"
    public static let results = "_agent/results"
    public static let resultsDone = "_agent/results/done"
}

public enum BridgeCoding {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }
    public static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
}

/// What Mustard writes to `_agent/outbox/<uid>.json` for the connected session to run.
public struct AgentWorkOrder: Codable, Equatable {
    public var uid: String
    public var mode: String          // "prep" | "execute"
    public var actionType: String    // RecommendationAction raw; "" for prep-to-classify
    public var title: String
    public var body: String
    public var area: String          // e.g. "Digital Licence"
    public var project: String       // KB code, e.g. "DL"
    public var sourceContext: String
    public var links: [TaskLink]
    public var createdAt: Date
    public init(uid: String, mode: String, actionType: String, title: String, body: String,
                area: String, project: String, sourceContext: String, links: [TaskLink], createdAt: Date) {
        self.uid = uid; self.mode = mode; self.actionType = actionType; self.title = title
        self.body = body; self.area = area; self.project = project
        self.sourceContext = sourceContext; self.links = links; self.createdAt = createdAt
    }
}

/// What the connected session writes to `_agent/results/<uid>.json`.
public struct AgentResult: Codable, Equatable {
    public var uid: String
    public var mode: String          // "prep" | "execute"
    public var status: String        // "done" | "failed" | "declined"
    public var actionType: String?   // prep: classified action
    public var title: String?        // prep: refined title
    public var body: String?         // prep: prepared draft
    public var links: [TaskLink]?    // execute: created artifact links
    public var summary: String?
    public var error: String?
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter BridgeProtocolTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/BridgeProtocol.swift Tests/MustardTests/BridgeProtocolTests.swift
git commit -m "feat(bridge): work-order/result schemas + folder constants"
```

---

## Task 2: BridgeExport (pure)

**Files:**
- Create: `Sources/MustardKit/Logic/BridgeExport.swift`
- Test: `Tests/MustardTests/BridgeExportTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MustardKit

final class BridgeExportTests: XCTestCase {
    private func task(_ stage: TaskStage, uid: String, action: RecommendationAction? = nil) -> MustardTask {
        let t = MustardTask(title: "t-\(uid)"); t.uid = uid; t.stage = stage
        if let action { t.actionType = action }
        return t
    }
    private let target = BridgeExport.RouteTarget(workingDir: "/kb/DL", project: "DL")
    private func route(_ t: MustardTask) -> BridgeExport.RouteTarget? { target }
    private let now = Date(timeIntervalSince1970: 1)

    func test_queuedTask_withoutOutbox_writesExecuteOrder() {
        let plan = BridgeExport.plan(tasks: [task(.queued, uid: "u1", action: .ticket)],
                                     route: route, liveOutboxUIDs: [:], now: now)
        XCTAssertEqual(plan.writes.count, 1)
        XCTAssertEqual(plan.writes[0].workingDir, "/kb/DL")
        XCTAssertEqual(plan.writes[0].order.uid, "u1")
        XCTAssertEqual(plan.writes[0].order.mode, "execute")
        XCTAssertEqual(plan.writes[0].order.actionType, "ticket_write")
        XCTAssertTrue(plan.cancels.isEmpty)
    }

    func test_forAgentTask_writesPrepOrder() {
        let plan = BridgeExport.plan(tasks: [task(.forAgent, uid: "u2")],
                                     route: route, liveOutboxUIDs: [:], now: now)
        XCTAssertEqual(plan.writes.first?.order.mode, "prep")
    }

    func test_taskWithLiveOutbox_isSkipped() {
        let plan = BridgeExport.plan(tasks: [task(.queued, uid: "u1")],
                                     route: route, liveOutboxUIDs: ["/kb/DL": ["u1"]], now: now)
        XCTAssertTrue(plan.writes.isEmpty)
    }

    func test_nonAgentStage_isIgnored() {
        let plan = BridgeExport.plan(tasks: [task(.planned, uid: "u3")],
                                     route: route, liveOutboxUIDs: [:], now: now)
        XCTAssertTrue(plan.writes.isEmpty)
    }

    func test_staleOutbox_isCancelled() {
        // live outbox u9, but no forAgent/queued task for it → cancel
        let plan = BridgeExport.plan(tasks: [task(.queued, uid: "u1")],
                                     route: route, liveOutboxUIDs: ["/kb/DL": ["u1", "u9"]], now: now)
        XCTAssertEqual(plan.cancels, [BridgeExport.Cancel(workingDir: "/kb/DL", uid: "u9")])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter BridgeExportTests`
Expected: FAIL — `BridgeExport` not defined.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum BridgeExport {
    public struct RouteTarget: Equatable { public let workingDir: String; public let project: String
        public init(workingDir: String, project: String) { self.workingDir = workingDir; self.project = project } }
    public struct Write: Equatable { public let workingDir: String; public let order: AgentWorkOrder }
    public struct Cancel: Equatable { public let workingDir: String; public let uid: String }
    public struct Plan: Equatable { public let writes: [Write]; public let cancels: [Cancel] }

    private static let exportStages: Set<TaskStage> = [.forAgent, .queued]

    /// `route` maps a task to its KB target (nil = unroutable → skipped).
    /// `liveOutboxUIDs` = uids with a live (non-archived) outbox file, keyed by workingDir.
    public static func plan(
        tasks: [MustardTask],
        route: (MustardTask) -> RouteTarget?,
        liveOutboxUIDs: [String: Set<String>],
        now: Date
    ) -> Plan {
        var writes: [Write] = []
        var activeByDir: [String: Set<String>] = [:]
        for t in tasks where exportStages.contains(t.stage) {
            guard let target = route(t) else { continue }
            activeByDir[target.workingDir, default: []].insert(t.uid)
            let live = liveOutboxUIDs[target.workingDir] ?? []
            if !live.contains(t.uid) {
                writes.append(Write(workingDir: target.workingDir, order: order(for: t, target: target, now: now)))
            }
        }
        var cancels: [Cancel] = []
        for (dir, uids) in liveOutboxUIDs {
            let active = activeByDir[dir] ?? []
            for uid in uids.sorted() where !active.contains(uid) {
                cancels.append(Cancel(workingDir: dir, uid: uid))
            }
        }
        return Plan(writes: writes, cancels: cancels)
    }

    static func order(for t: MustardTask, target: RouteTarget, now: Date) -> AgentWorkOrder {
        AgentWorkOrder(
            uid: t.uid,
            mode: t.stage == .forAgent ? "prep" : "execute",
            actionType: t.actionType?.rawValue ?? "",
            title: t.title, body: t.notes,
            area: t.list?.area?.name ?? "",
            project: target.project,
            sourceContext: t.sourceContext,
            links: t.links, createdAt: now)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter BridgeExportTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/BridgeExport.swift Tests/MustardTests/BridgeExportTests.swift
git commit -m "feat(bridge): pure export planner (writes + stale cancels)"
```

---

## Task 3: BridgeIngest (pure, guarded apply)

**Files:**
- Create: `Sources/MustardKit/Logic/BridgeIngest.swift`
- Test: `Tests/MustardTests/BridgeIngestTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MustardKit

final class BridgeIngestTests: XCTestCase {
    private func task(_ stage: TaskStage, uid: String = "u1") -> MustardTask {
        let t = MustardTask(title: "t"); t.uid = uid; t.stage = stage; return t
    }
    private func result(mode: String, status: String, links: [TaskLink]? = nil,
                        actionType: String? = nil, body: String? = nil, summary: String? = nil) -> AgentResult {
        AgentResult(uid: "u1", mode: mode, status: status, actionType: actionType,
                    title: nil, body: body, links: links, summary: summary, error: nil)
    }

    func test_executeDone_setsLinks_andNeedsReview() {
        let t = task(.queued)
        let out = BridgeIngest.apply(result(mode: "execute", status: "done",
            links: [TaskLink(label: "Shortcut", url: "https://app.shortcut.com/x")], summary: "made it"), to: t)
        XCTAssertEqual(out, .applied)
        XCTAssertEqual(t.stage, .needsReview)
        XCTAssertEqual(t.links.first?.url, "https://app.shortcut.com/x")
    }

    func test_prepDone_setsDraftAndAction_andNeedsApproval() {
        let t = task(.forAgent)
        let out = BridgeIngest.apply(result(mode: "prep", status: "done",
            actionType: "ticket_write", body: "prepared"), to: t)
        XCTAssertEqual(out, .applied)
        XCTAssertEqual(t.stage, .needsApproval)
        XCTAssertEqual(t.actionType, .ticket)
        XCTAssertEqual(t.notes, "prepared")
    }

    func test_staleStage_isIgnored_notApplied() {
        let t = task(.done)   // task already moved on
        let out = BridgeIngest.apply(result(mode: "execute", status: "done",
            links: [TaskLink(label: "x", url: "y")]), to: t)
        XCTAssertEqual(out, .staleIgnored)
        XCTAssertEqual(t.stage, .done)   // untouched
    }

    func test_doubleApply_isNoOp() {
        let t = task(.queued)
        let r = result(mode: "execute", status: "done", links: [TaskLink(label: "x", url: "y")])
        XCTAssertEqual(BridgeIngest.apply(r, to: t), .applied)      // → needsReview
        XCTAssertEqual(BridgeIngest.apply(r, to: t), .staleIgnored) // stage no longer queued
    }

    func test_unknownTask_isUnknown() {
        XCTAssertEqual(BridgeIngest.apply(result(mode: "execute", status: "done"), to: nil), .unknownTask)
    }

    func test_executeFailed_staysQueued() {
        let t = task(.queued)
        let out = BridgeIngest.apply(result(mode: "execute", status: "failed"), to: t)
        XCTAssertEqual(out, .applied)
        XCTAssertEqual(t.stage, .queued)   // left for retry
    }

    func test_prepDeclined_returnsToMe() {
        let t = task(.forAgent)
        _ = BridgeIngest.apply(result(mode: "prep", status: "declined", summary: "not mine"), to: t)
        XCTAssertEqual(t.owner, .me)
        XCTAssertEqual(t.stage, .planned)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter BridgeIngestTests`
Expected: FAIL — `BridgeIngest` not defined.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum BridgeIngest {
    public enum Outcome: Equatable { case applied, staleIgnored, unknownTask }

    /// Apply a result to its task under the stage guard (prep→forAgent, execute→queued).
    /// Mutates `task`. The caller archives the file for EVERY outcome. `failed` leaves the
    /// task at its source stage (so the next export re-issues the work order — retry).
    @discardableResult
    public static func apply(_ r: AgentResult, to task: MustardTask?) -> Outcome {
        guard let task else { return .unknownTask }
        let sourceStage: TaskStage = (r.mode == "prep") ? .forAgent : .queued
        guard task.stage == sourceStage else { return .staleIgnored }

        switch (r.mode, r.status) {
        case ("prep", "done"):
            if let a = r.actionType, !a.isEmpty { task.actionTypeRaw = a }
            if let b = r.body { task.notes = b }
            if let t = r.title, !t.isEmpty { task.title = t }
            task.stage = .needsApproval
        case ("execute", "done"):
            task.links = r.links ?? []
            if let s = r.summary, !s.isEmpty {
                task.notes += (task.notes.isEmpty ? "" : "\n\n") + "🤖 Agent output:\n\(s)"
            }
            task.stage = .needsReview
        case (_, "declined"):
            task.owner = .me; task.stage = .planned
            let why = (r.summary ?? "").isEmpty ? "." : ": \(r.summary!)"
            task.notes += (task.notes.isEmpty ? "" : "\n\n") + "🤖 Agent passed on this\(why)"
        case (_, "failed"):
            break   // stay at source stage; caller surfaces r.error
        default:
            break   // unknown combo: no-op (still archived)
        }
        return .applied
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter BridgeIngestTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/BridgeIngest.swift Tests/MustardTests/BridgeIngestTests.swift
git commit -m "feat(bridge): pure guarded result ingest"
```

---

## Task 4: BridgeIO (FileManager wrapper)

**Files:**
- Create: `Sources/MustardKit/Agent/BridgeIO.swift`
- Test: `Tests/MustardTests/FileBridgeIOTests.swift`

- [ ] **Step 1: Write the failing test** (real temp dir)

```swift
import XCTest
@testable import MustardKit

final class FileBridgeIOTests: XCTestCase {
    private var dir: String!
    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "bridge-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: dir) }

    func test_write_list_then_cancel() throws {
        let io = FileBridgeIO()
        let o = AgentWorkOrder(uid: "u1", mode: "execute", actionType: "ticket_write", title: "t",
            body: "b", area: "Digital Licence", project: "DL", sourceContext: "", links: [],
            createdAt: Date(timeIntervalSince1970: 1))
        try io.writeWorkOrder(o, workingDir: dir)
        XCTAssertEqual(io.liveOutboxUIDs(workingDir: dir), ["u1"])
        try io.cancelWorkOrder(uid: "u1", workingDir: dir)
        XCTAssertTrue(io.liveOutboxUIDs(workingDir: dir).isEmpty)
    }

    func test_readResults_thenArchive() throws {
        let io = FileBridgeIO()
        let resultsDir = dir + "/" + BridgeFolders.results
        try FileManager.default.createDirectory(atPath: resultsDir, withIntermediateDirectories: true)
        let json = #"{"uid":"u1","mode":"execute","status":"done"}"#
        try json.write(toFile: resultsDir + "/u1.json", atomically: true, encoding: .utf8)

        let read = io.readResults(workingDir: dir)
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].result.uid, "u1")

        try io.archiveResult(read[0].path, workingDir: dir)
        XCTAssertTrue(io.readResults(workingDir: dir).isEmpty)              // gone from results/
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/" + BridgeFolders.resultsDone + "/u1.json"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FileBridgeIOTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// File operations the bridge needs; injected so the service is testable with a stub.
public protocol BridgeIO {
    func liveOutboxUIDs(workingDir: String) -> Set<String>
    func writeWorkOrder(_ order: AgentWorkOrder, workingDir: String) throws
    func cancelWorkOrder(uid: String, workingDir: String) throws
    func readResults(workingDir: String) -> [(result: AgentResult, path: String)]
    func archiveResult(_ path: String, workingDir: String) throws
}

public struct FileBridgeIO: BridgeIO {
    public init() {}
    private var fm: FileManager { .default }

    public func liveOutboxUIDs(workingDir: String) -> Set<String> {
        let p = workingDir + "/" + BridgeFolders.outbox
        guard let files = try? fm.contentsOfDirectory(atPath: p) else { return [] }
        return Set(files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) })
    }

    public func writeWorkOrder(_ order: AgentWorkOrder, workingDir: String) throws {
        let dir = workingDir + "/" + BridgeFolders.outbox
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try BridgeCoding.encoder.encode(order).write(to: URL(fileURLWithPath: dir + "/\(order.uid).json"))
    }

    public func cancelWorkOrder(uid: String, workingDir: String) throws {
        let path = workingDir + "/" + BridgeFolders.outbox + "/\(uid).json"
        if fm.fileExists(atPath: path) { try fm.removeItem(atPath: path) }
    }

    public func readResults(workingDir: String) -> [(result: AgentResult, path: String)] {
        let p = workingDir + "/" + BridgeFolders.results
        guard let files = try? fm.contentsOfDirectory(atPath: p) else { return [] }
        return files.filter { $0.hasSuffix(".json") }.sorted().compactMap { name in
            let path = p + "/" + name
            guard let data = fm.contents(atPath: path),
                  let r = try? BridgeCoding.decoder.decode(AgentResult.self, from: data),
                  !r.uid.isEmpty else { return nil }
            return (r, path)
        }
    }

    public func archiveResult(_ path: String, workingDir: String) throws {
        let doneDir = workingDir + "/" + BridgeFolders.resultsDone
        try fm.createDirectory(atPath: doneDir, withIntermediateDirectories: true)
        let dest = doneDir + "/" + (path as NSString).lastPathComponent
        if fm.fileExists(atPath: dest) { try fm.removeItem(atPath: dest) }
        try fm.moveItem(atPath: path, toPath: dest)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter FileBridgeIOTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Agent/BridgeIO.swift Tests/MustardTests/FileBridgeIOTests.swift
git commit -m "feat(bridge): FileManager BridgeIO (outbox write/cancel, results read/archive)"
```

---

## Task 5: AgentService orchestration

**Files:**
- Modify: `Sources/MustardKit/Agent/AgentService.swift`
- Test: `Tests/MustardTests/AgentBridgeServiceTests.swift`

- [ ] **Step 1: Add an injected `BridgeIO` to `AgentService`**

In the stored properties add `private let bridge: BridgeIO`, and extend `init` to accept it with a default:

```swift
    public init(context: ModelContext, claude: @escaping ClaudeRun = ClaudeRunner.run,
                bridge: BridgeIO = FileBridgeIO()) {
        self.context = context
        self.claude = claude
        self.bridge = bridge
    }
```

- [ ] **Step 2: Write the failing test** (stub IO)

```swift
import XCTest
import SwiftData
@testable import MustardKit

final class AgentBridgeServiceTests: XCTestCase {
    final class StubIO: BridgeIO {
        var written: [AgentWorkOrder] = []
        var cancelled: [String] = []
        var archived: [String] = []
        var live: Set<String> = []
        var results: [(AgentResult, String)] = []
        func liveOutboxUIDs(workingDir: String) -> Set<String> { live }
        func writeWorkOrder(_ order: AgentWorkOrder, workingDir: String) throws { written.append(order) }
        func cancelWorkOrder(uid: String, workingDir: String) throws { cancelled.append(uid) }
        func readResults(workingDir: String) -> [(result: AgentResult, path: String)] { results.map { ($0.0, $0.1) } }
        func archiveResult(_ path: String, workingDir: String) throws { archived.append(path) }
    }

    @MainActor
    private func service(_ io: StubIO) throws -> (AgentService, ModelContext) {
        let c = try ModelContainer(for: Area.self, TaskList.self, MustardTask.self, Recommendation.self,
                                   CalendarEvent.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        return (AgentService(context: ctx, claude: { _, _ in .init(ok: true, text: "") }, bridge: io), ctx)
    }

    @MainActor
    func test_export_writesQueuedTask() throws {
        let io = StubIO(); let (svc, ctx) = try service(io)
        let t = MustardTask(title: "ship"); t.uid = "u1"; t.stage = .queued; t.actionType = .ticket
        ctx.insert(t)
        svc.exportWorkOrders(workingDir: "/kb/DL", area: "Digital Licence", project: "DL")
        XCTAssertEqual(io.written.map(\.uid), ["u1"])
        XCTAssertEqual(io.written.first?.mode, "execute")
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
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --filter AgentBridgeServiceTests`
Expected: FAIL — methods not defined.

- [ ] **Step 4: Implement the two methods on `AgentService`**

```swift
    /// Export forAgent/queued tasks under one KB working dir to its `_agent/outbox/`,
    /// and cancel stale outbox files. Pure plan + injected IO. (area/project identify
    /// the KB; in the loop these come from the SourceConfig + AreaRouter map.)
    public func exportWorkOrders(workingDir: String, area: String, project: String) {
        let all = (try? context.fetch(FetchDescriptor<MustardTask>())) ?? []
        // This dir handles tasks whose area maps here; the caller passes the dir/area/project.
        let target = BridgeExport.RouteTarget(workingDir: workingDir, project: project)
        let mine = all.filter { ($0.list?.area?.name ?? "") == area }
        let plan = BridgeExport.plan(
            tasks: mine, route: { _ in target },
            liveOutboxUIDs: [workingDir: bridge.liveOutboxUIDs(workingDir: workingDir)], now: .now)
        for w in plan.writes { try? bridge.writeWorkOrder(w.order, workingDir: workingDir) }
        for c in plan.cancels { try? bridge.cancelWorkOrder(uid: c.uid, workingDir: workingDir) }
    }

    /// Ingest `_agent/results/` for one KB working dir: apply each (guarded) and archive it.
    public func ingestAgentResults(workingDir: String) {
        let all = (try? context.fetch(FetchDescriptor<MustardTask>())) ?? []
        let byUID = Dictionary(all.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        for (result, path) in bridge.readResults(workingDir: workingDir) {
            let outcome = BridgeIngest.apply(result, to: byUID[result.uid])
            if outcome == .applied, result.status == "failed" {
                lastError = "Agent run failed: \(result.error ?? "unknown")"
            }
            try? bridge.archiveResult(path, workingDir: workingDir)
        }
    }
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter AgentBridgeServiceTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Agent/AgentService.swift Tests/MustardTests/AgentBridgeServiceTests.swift
git commit -m "feat(bridge): AgentService export + ingest orchestration"
```

---

## Task 6: Wire into the app loop

**Files:**
- Modify: `Sources/Mustard/MustardApp.swift`

- [ ] **Step 1: In the ~10-min throttled block (where `ingestInbox` is called), add export + ingest per enabled vault source.**

For each `source` already iterated for `ingestInbox`, after the inbox ingest, call:

```swift
                    // Agent bridge: export queued/forAgent tasks + ingest results (Phase 2).
                    let areaName = MeetingTaskSync.defaultAreaMap[source.project] ?? ""
                    if !areaName.isEmpty {
                        agent.exportWorkOrders(workingDir: source.workingDirectory, area: areaName, project: source.project)
                        agent.ingestAgentResults(workingDir: source.workingDirectory)
                    }
```

(The `defaultAreaMap` is `["DL": "Digital Licence", ...]`; `source.project` is the KB code. Only sources whose project maps to an area participate.)

- [ ] **Step 2: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add Sources/Mustard/MustardApp.swift
git commit -m "feat(bridge): run export + result ingest on the 10-min loop"
```

---

## Task 7: Contract doc + manual test

**Files:**
- Create: `docs/agent-bridge-contract.md`

- [ ] **Step 1: Write the contract doc** — the folder protocol + both JSON schemas + the apply table from the spec, framed as the interface Phase 3's worker implements. Include a worked example `outbox/<uid>.json` and `results/<uid>.json`.

- [ ] **Step 2: Manual end-to-end test (record in the doc).**
  1. In the app, approve an outward recommendation so a task enters `Approved · Queued`.
  2. Confirm `<KB>/_agent/outbox/<uid>.json` appears with `mode:"execute"`.
  3. Hand-write `<KB>/_agent/results/<uid>.json`: `{"uid":"<uid>","mode":"execute","status":"done","links":[{"label":"Shortcut","url":"https://app.shortcut.com/x"}],"summary":"created"}`.
  4. Wait for the loop (or relaunch); confirm the task moved to `Needs Review` with the link, and the result file is now under `results/done/`.

- [ ] **Step 3: Commit**

```bash
git add docs/agent-bridge-contract.md
git commit -m "docs(bridge): Phase 2 file contract + manual test"
```

---

## Self-review

**Spec coverage:** folder protocol → Task 1 (constants) + Task 4 (IO); work-order/result schemas → Task 1; export (writes + stale cancel) → Task 2 + Task 5; guarded ingest + apply table → Task 3 + Task 5; archive-on-consume → Task 4 (results) + the session side documented in Task 7 (Phase 3); loop trigger → Task 6; AreaRouter routing → Task 5/6 via `defaultAreaMap`; mobile constraint (export = pure function of board state) → Task 2 (no Mac-only inputs); Phase 3 boundary + manual test → Task 7.

**Placeholder scan:** none — every code step is complete; Task 7's doc content is enumerated.

**Type consistency:** `AgentWorkOrder`/`AgentResult`/`TaskLink`/`BridgeFolders`/`BridgeCoding` (Task 1) used consistently in 2–5; `BridgeExport.{RouteTarget,Write,Cancel,Plan}` (Task 2) match Task 5 callers; `BridgeIngest.Outcome` (Task 3) matches Task 5; `BridgeIO` protocol (Task 4) matches the Task 5 stub + `FileBridgeIO`. `exportWorkOrders(workingDir:area:project:)` / `ingestAgentResults(workingDir:)` signatures match between Task 5 definition and Task 6 callers.

**Note:** Task 5's `route` closure collapses to a single target because the caller pre-filters tasks to one KB by `area`; the multi-dir `BridgeExport.plan` is still exercised per-source across the loop. Stale-cancel is scoped per working dir, which is correct (each KB owns its own outbox).
