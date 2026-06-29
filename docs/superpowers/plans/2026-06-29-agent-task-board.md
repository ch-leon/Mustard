# Agent Task Board Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Mustard's me-only Board into an owner-segmented board that surfaces your tasks and the agent's tasks together, driven by a single `stage` field, with approving agent work staging it in a queue for a (later) decoupled session.

**Architecture:** Replace `TaskStatus` + derived `DelegationPhase` with one `TaskStage` on `MustardTask`; rewrite `PersonalBoard` to bucket by stage and return per-view column sets; add the promotion wiring (console Approve → `queued`; delegate → `forAgent`); rebuild `BoardView`/`MustardBoardCard` from the design handoff; retire `OutputCard`. Execution (Phase 2/3) is out of scope.

**Tech Stack:** Swift Package, SwiftUI, SwiftData, XCTest. Logic is TDD; views are verified by `swift build` + Leon's eye (CLAUDE.md).

**Spec:** `docs/specs/2026-06-29-agent-task-board-design.md`
**Visual source of truth:** `~/Downloads/design_handoff_agent_board/` (exact hex/sizes in its `README.md`).

---

## File structure

**Create:**
- `Sources/MustardKit/Models/TaskStage.swift` — `TaskStage` enum (10 stages) + `TaskColumnKind` + per-view column sets + `TaskLink`.
- `Sources/MustardKit/Logic/BoardMigration.swift` — pure legacy-`status` → `stage` mapping + a one-time backfill.
- `Sources/MustardKit/Logic/RecommendationPromotion.swift` — pure "what stage/owner does an approved/scheduled rec become" logic.
- `Sources/MustardKit/Logic/BoardSettings.swift` — `defaultView` / `density` / `showConfidence` (UserDefaults-backed).
- `Sources/MustardKit/Views/MustardBoardCard.swift` — the card.
- `Tests/MustardTests/TaskStageTests.swift`, `BoardMigrationTests.swift`, `RecommendationPromotionTests.swift` — and extend `PersonalBoardTests.swift`.

**Modify:**
- `Sources/MustardKit/Models/Enums.swift` — keep `TaskStatus` only as a legacy decode target (see Task 2); `TaskOwner` unchanged.
- `Sources/MustardKit/Models/MustardTask.swift` — add `stageRaw`/`stage`, `links`, `actionTypeRaw`/`actionType`, `confidence`; keep `statusRaw` as legacy-only.
- `Sources/MustardKit/Logic/PersonalBoard.swift` — rewrite to stage + views + filters.
- `Sources/MustardKit/Agent/AgentService.swift` — approve promotes to `queued`; delegate sets `forAgent`; remove `OutputCard` usage.
- `Sources/MustardKit/Views/BoardView.swift` — full rebuild per handoff.
- `Sources/MustardKit/MustardContainer.swift` — run `BoardMigration.backfill` once after the container is built; drop `OutputCard` from the schema.
- `Sources/MustardKit/Views/{TodayView,WeekView,HoverPanel,NotchSurface,AgentConsoleView}.swift` + `Logic/{DayPlanner,WeekPlanner}.swift` — replace `status`/`DelegationPhase` reads with `stage`.

**Delete (Task 6):**
- `Sources/MustardKit/Models/Recommendation.swift` → remove the `OutputCard` `@Model`.
- `Sources/MustardKit/Logic/DelegationPhase.swift` and its tests.

---

## Task 1: TaskStage, column kind, views, TaskLink

**Files:**
- Create: `Sources/MustardKit/Models/TaskStage.swift`
- Test: `Tests/MustardTests/TaskStageTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MustardKit

final class TaskStageTests: XCTestCase {
    func test_allViews_includeInboxAndDone() {
        for view in BoardOwnerView.allCases {
            XCTAssertTrue(view.columns.contains(.inbox), "\(view) missing inbox")
            XCTAssertTrue(view.columns.contains(.done), "\(view) missing done")
        }
    }

    func test_mineView_hasNoAgentStages() {
        let agentStages: Set<TaskStage> = [.forAgent, .needsApproval, .queued, .needsReview]
        XCTAssertTrue(BoardOwnerView.mine.columns.allSatisfy { !agentStages.contains($0) })
    }

    func test_everyoneView_isTheFullPipelineInOrder() {
        XCTAssertEqual(BoardOwnerView.everyone.columns,
            [.inbox, .planned, .scheduled, .forAgent, .needsApproval,
             .queued, .needsReview, .inProgress, .blocked, .done])
    }

    func test_agentView_columns() {
        XCTAssertEqual(BoardOwnerView.agent.columns,
            [.inbox, .forAgent, .needsApproval, .queued, .needsReview, .done])
    }

    func test_kind_perStage() {
        XCTAssertEqual(TaskStage.forAgent.kind, .handoff)
        XCTAssertEqual(TaskStage.needsApproval.kind, .gate)
        XCTAssertEqual(TaskStage.queued.kind, .agent)
        XCTAssertEqual(TaskStage.needsReview.kind, .gate)
        XCTAssertEqual(TaskStage.blocked.kind, .warn)
        XCTAssertEqual(TaskStage.done.kind, .done)
        XCTAssertEqual(TaskStage.planned.kind, .standard)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TaskStageTests`
Expected: FAIL — `TaskStage` / `BoardOwnerView` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum TaskStage: String, Codable, CaseIterable, Identifiable {
    case inbox, planned, scheduled, forAgent, needsApproval,
         queued, needsReview, inProgress, blocked, done
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .inbox: "Inbox"
        case .planned: "Planned"
        case .scheduled: "Scheduled"
        case .forAgent: "For Agent"
        case .needsApproval: "Needs Approval"
        case .queued: "Approved · Queued"
        case .needsReview: "Needs Review"
        case .inProgress: "In Progress"
        case .blocked: "Blocked"
        case .done: "Done"
        }
    }

    public var subLabel: String? {
        switch self {
        case .forAgent: "agent picks up & preps"
        case .needsApproval: "approve before it runs"
        case .needsReview: "check the output"
        default: nil
        }
    }

    public var kind: TaskColumnKind {
        switch self {
        case .forAgent: .handoff
        case .needsApproval, .needsReview: .gate
        case .queued: .agent
        case .blocked: .warn
        case .done: .done
        default: .standard
        }
    }

    /// Open == still actionable (excludes done).
    public var isOpen: Bool { self != .done }
}

public enum TaskColumnKind: String { case standard, handoff, gate, agent, warn, done }

public enum BoardOwnerView: String, CaseIterable, Identifiable {
    case everyone, mine, agent
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .everyone: "Everyone"
        case .mine: "Mine"
        case .agent: "✦ Agent"
        }
    }

    public var caption: String {
        switch self {
        case .everyone: "Everyone — the full pipeline, yours and the agent’s together."
        case .mine: "Mine — just your own work."
        case .agent: "Agent — hand-offs run through For Agent → Needs Approval → Needs Review."
        }
    }

    public var columns: [TaskStage] {
        switch self {
        case .everyone:
            [.inbox, .planned, .scheduled, .forAgent, .needsApproval,
             .queued, .needsReview, .inProgress, .blocked, .done]
        case .mine:
            [.inbox, .planned, .scheduled, .inProgress, .blocked, .done]
        case .agent:
            [.inbox, .forAgent, .needsApproval, .queued, .needsReview, .done]
        }
    }
}

/// A link shown on a Needs Review card (Shortcut/Jira/draft).
public struct TaskLink: Codable, Hashable {
    public var label: String
    public var url: String
    public init(label: String, url: String) { self.label = label; self.url = url }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TaskStageTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Models/TaskStage.swift Tests/MustardTests/TaskStageTests.swift
git commit -m "feat(board): TaskStage, column kinds, per-view column sets"
```

---

## Task 2: MustardTask — stage, links, actionType, confidence (+ legacy status)

**Files:**
- Modify: `Sources/MustardKit/Models/MustardTask.swift`
- Modify: `Sources/MustardKit/Models/Enums.swift` (keep `TaskStatus`; mark legacy in a comment)

- [ ] **Step 1: Add the stored fields + computed accessors to `MustardTask`**

In the `@Model`, add alongside the existing `statusRaw` (which stays for legacy decode/backfill only):

```swift
    public var stageRaw: String = TaskStage.inbox.rawValue
    public var actionTypeRaw: String? = nil
    public var confidence: Double? = nil
    public var links: [TaskLink] = []
```

Add computed accessors near the existing `status` computed property:

```swift
    public var stage: TaskStage {
        get { TaskStage(rawValue: stageRaw) ?? .inbox }
        set { stageRaw = newValue.rawValue }
    }

    public var actionType: RecommendationAction? {
        get { actionTypeRaw.flatMap(RecommendationAction.init(rawValue:)) }
        set { actionTypeRaw = newValue?.rawValue }
    }

    /// Outward/connector actions are always gated (reuse the rec policy).
    public var isGated: Bool { actionType?.isGated ?? false }
```

Update `markDone(now:)` to set `stage = .done` (in addition to whatever it does today):

```swift
    public func markDone(now: Date = .now) {
        stage = .done
        statusRaw = TaskStatus.done.rawValue   // keep legacy in sync during transition
        completedAt = now
        // ... existing subtask cascade unchanged ...
    }
```

- [ ] **Step 2: Add a deprecation note in `Enums.swift`**

Above `TaskStatus`, add:

```swift
/// LEGACY: superseded by `TaskStage`. Retained only so existing stores decode and
/// `BoardMigration` can backfill `stage`. Do not use in new code.
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: builds (existing `status` readers still compile; we migrate them in later tasks).

- [ ] **Step 4: Commit**

```bash
git add Sources/MustardKit/Models/MustardTask.swift Sources/MustardKit/Models/Enums.swift
git commit -m "feat(board): add stage/links/actionType/confidence to MustardTask"
```

---

## Task 3: BoardMigration — legacy status → stage

**Files:**
- Create: `Sources/MustardKit/Logic/BoardMigration.swift`
- Test: `Tests/MustardTests/BoardMigrationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MustardKit

final class BoardMigrationTests: XCTestCase {
    func test_meTask_mapsByStatus() {
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .inbox, scheduledAt: nil, owner: .me), .inbox)
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .inProgress, scheduledAt: nil, owner: .me), .inProgress)
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .done, scheduledAt: nil, owner: .me), .done)
    }

    func test_someday_collapsesToInbox() {
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .someday, scheduledAt: nil, owner: .me), .inbox)
    }

    func test_plannedWithDate_becomesScheduled() {
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .planned, scheduledAt: Date(timeIntervalSince1970: 1), owner: .me), .scheduled)
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .planned, scheduledAt: nil, owner: .me), .planned)
    }

    func test_agentTask_landsInQueued() {
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .inProgress, scheduledAt: nil, owner: .agent), .queued)
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .done, scheduledAt: nil, owner: .agent), .done)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BoardMigrationTests`
Expected: FAIL — `BoardMigration` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import SwiftData

public enum BoardMigration {
    /// Pure mapping of a pre-stage task to a `TaskStage`. Accepts the deliberate
    /// data loss agreed in the spec: `someday` collapses into `inbox`; any open
    /// agent-owned task lands in `queued` (re-triage from there).
    public static func stage(legacyStatus: TaskStatus, scheduledAt: Date?, owner: TaskOwner) -> TaskStage {
        if owner == .agent { return legacyStatus == .done ? .done : .queued }
        switch legacyStatus {
        case .inbox: return .inbox
        case .someday: return .inbox
        case .planned: return scheduledAt != nil ? .scheduled : .planned
        case .inProgress: return .inProgress
        case .done: return .done
        }
    }

    /// One-time backfill: any task whose `stageRaw` is still the default while it
    /// has a legacy `statusRaw` gets its stage set. Idempotent — re-running is safe
    /// because already-migrated tasks have a non-inbox stage or a marker.
    public static func backfill(_ context: ModelContext) {
        let fetch = FetchDescriptor<MustardTask>()
        guard let tasks = try? context.fetch(fetch) else { return }
        for t in tasks where !t.migratedStage {
            let legacy = TaskStatus(rawValue: t.statusRaw) ?? .inbox
            t.stage = stage(legacyStatus: legacy, scheduledAt: t.scheduledAt, owner: t.owner)
            t.migratedStage = true
        }
    }
}
```

- [ ] **Step 4: Add the `migratedStage` marker to `MustardTask`**

In the `@Model` add: `public var migratedStage: Bool = false`

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter BoardMigrationTests`
Expected: PASS.

- [ ] **Step 6: Wire the backfill into the container**

In `MustardContainer.swift`, after the `ModelContainer` is created, run once on its main context:

```swift
        BoardMigration.backfill(container.mainContext)
        try? container.mainContext.save()
```

- [ ] **Step 7: Build + commit**

Run: `swift build`
```bash
git add Sources/MustardKit/Logic/BoardMigration.swift Sources/MustardKit/Models/MustardTask.swift Sources/MustardKit/MustardContainer.swift Tests/MustardTests/BoardMigrationTests.swift
git commit -m "feat(board): migrate legacy status to stage on launch"
```

---

## Task 4: PersonalBoard — bucket by stage, per-view columns, filters

**Files:**
- Modify: `Sources/MustardKit/Logic/PersonalBoard.swift`
- Test: `Tests/MustardTests/PersonalBoardTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MustardKit

final class PersonalBoardTests: XCTestCase {
    private func task(_ stage: TaskStage, owner: TaskOwner = .me, area: String? = nil) -> MustardTask {
        let t = MustardTask(title: "t"); t.stage = stage; t.owner = owner
        if let area { let a = Area(name: area, colorHex: "#000"); let l = TaskList(name: "l"); l.area = a; t.list = l }
        return t
    }

    func test_columnsForView_matchOwnerView() {
        XCTAssertEqual(PersonalBoard.columns(for: .mine), BoardOwnerView.mine.columns)
        XCTAssertEqual(PersonalBoard.columns(for: .agent), BoardOwnerView.agent.columns)
    }

    func test_bucket_filtersByStage() {
        let all = [task(.inbox), task(.queued, owner: .agent), task(.inbox)]
        XCTAssertEqual(PersonalBoard.tasks(all, in: .inbox, view: .everyone, area: .all).count, 2)
        XCTAssertEqual(PersonalBoard.tasks(all, in: .queued, view: .everyone, area: .all).count, 1)
    }

    func test_mineView_excludesAgentOwned() {
        let all = [task(.inbox, owner: .me), task(.inbox, owner: .agent)]
        XCTAssertEqual(PersonalBoard.tasks(all, in: .inbox, view: .mine, area: .all).count, 1)
    }

    func test_agentView_excludesMeOwned() {
        let all = [task(.inbox, owner: .me), task(.inbox, owner: .agent)]
        XCTAssertEqual(PersonalBoard.tasks(all, in: .inbox, view: .agent, area: .all).count, 1)
    }

    func test_areaFilter_combinesWithOwner_andPersonalIsErrandsOrReading() {
        let all = [task(.inbox, area: "Errands"), task(.inbox, area: "DLA SDK")]
        XCTAssertEqual(PersonalBoard.tasks(all, in: .inbox, view: .everyone, area: .personal).count, 1)
    }

    func test_waitingCount_isNeedsApprovalPlusNeedsReview_inScope() {
        let all = [task(.needsApproval, owner: .agent), task(.needsReview, owner: .agent), task(.inbox)]
        XCTAssertEqual(PersonalBoard.waitingCount(all, view: .everyone, area: .all), 2)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PersonalBoardTests`
Expected: FAIL — new signatures not defined (and old `tasks(_:status:)` referenced by tests is gone).

- [ ] **Step 3: Rewrite `PersonalBoard`**

```swift
import Foundation

public enum BoardArea: Equatable {
    case all, area(String), personal
}

public enum PersonalBoard {
    public static func columns(for view: BoardOwnerView) -> [TaskStage] { view.columns }

    public static func tasks(_ all: [MustardTask], in stage: TaskStage,
                             view: BoardOwnerView, area: BoardArea) -> [MustardTask] {
        all.filter { $0.stage == stage && ownerOK($0, view) && areaOK($0, area) }
            .sorted { sortKey($0) < sortKey($1) }
    }

    public static func waitingCount(_ all: [MustardTask], view: BoardOwnerView, area: BoardArea) -> Int {
        all.filter { ($0.stage == .needsApproval || $0.stage == .needsReview)
            && ownerOK($0, view) && areaOK($0, area) }.count
    }

    /// Unfiltered agent attention badge (sidebar): needs approval + needs review, all tasks.
    public static func agentBadge(_ all: [MustardTask]) -> Int {
        all.filter { $0.stage == .needsApproval || $0.stage == .needsReview }.count
    }

    private static func ownerOK(_ t: MustardTask, _ view: BoardOwnerView) -> Bool {
        switch view {
        case .everyone: return true
        case .mine: return t.owner == .me
        case .agent: return t.owner == .agent
        }
    }

    private static func areaOK(_ t: MustardTask, _ area: BoardArea) -> Bool {
        switch area {
        case .all: return true
        case .area(let name): return t.list?.area?.name == name
        case .personal:
            let n = t.list?.area?.name
            return n == "Errands" || n == "Reading"
        }
    }

    /// Done sorts by completedAt desc; everything else by createdAt asc.
    private static func sortKey(_ t: MustardTask) -> Double {
        t.stage == .done ? -(t.completedAt ?? .distantPast).timeIntervalSince1970
                         : t.createdAt.timeIntervalSince1970
    }

    /// Apply a column move (drag): set stage, keep completedAt consistent with done.
    public static func move(_ t: MustardTask, to stage: TaskStage, now: Date = .now) {
        if stage == .done { t.markDone(now: now) }
        else { t.stage = stage; t.completedAt = nil }
    }

    /// Card owner toggle: to agent → forAgent; to me → planned; done keeps its stage.
    public static func reassign(_ t: MustardTask, to owner: TaskOwner) {
        guard t.owner != owner else { return }
        t.owner = owner
        if t.stage != .done { t.stage = owner == .agent ? .forAgent : .planned }
    }

    public static let doneColumnLimit = 15
    public static func olderDoneCount(_ all: [MustardTask], view: BoardOwnerView, area: BoardArea,
                                      limit: Int = doneColumnLimit) -> Int {
        max(0, tasks(all, in: .done, view: view, area: area).count - limit)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter PersonalBoardTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/PersonalBoard.swift Tests/MustardTests/PersonalBoardTests.swift
git commit -m "feat(board): bucket by stage with per-view + area filters"
```

---

## Task 5: RecommendationPromotion — approve → queued, schedule → scheduled

**Files:**
- Create: `Sources/MustardKit/Logic/RecommendationPromotion.swift`
- Test: `Tests/MustardTests/RecommendationPromotionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MustardKit

final class RecommendationPromotionTests: XCTestCase {
    func test_approve_outwardAction_goesToQueuedAgentOwned() {
        let p = RecommendationPromotion.plan(action: .draftEmail, decision: .approved)
        XCTAssertEqual(p.stage, .queued); XCTAssertEqual(p.owner, .agent)
    }
    func test_approve_inVaultAction_goesStraightToDone() {
        let p = RecommendationPromotion.plan(action: .vaultNote, decision: .approved)
        XCTAssertEqual(p.stage, .done); XCTAssertEqual(p.owner, .agent)
    }
    func test_schedule_becomesScheduledMeTask() {
        let p = RecommendationPromotion.plan(action: .draftEmail, decision: .scheduled)
        XCTAssertEqual(p.stage, .scheduled); XCTAssertEqual(p.owner, .me)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter RecommendationPromotionTests`
Expected: FAIL — `RecommendationPromotion` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum RecommendationPromotion {
    public struct Plan: Equatable { public let stage: TaskStage; public let owner: TaskOwner }

    /// Where an approved/scheduled recommendation lands on the board.
    /// In-vault actions (vault note, create task) can run headless → Done.
    /// Outward/connector actions queue for the decoupled session.
    public static func plan(action: RecommendationAction, decision: RecommendationDecision) -> Plan {
        switch decision {
        case .scheduled: return Plan(stage: .scheduled, owner: .me)
        case .selfExecute: return Plan(stage: .planned, owner: .me)
        case .approved:
            let inVault = (action == .vaultNote || action == .createTask)
            return Plan(stage: inVault ? .done : .queued, owner: .agent)
        default: return Plan(stage: .inbox, owner: .me)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter RecommendationPromotionTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/RecommendationPromotion.swift Tests/MustardTests/RecommendationPromotionTests.swift
git commit -m "feat(board): recommendation promotion plan (approve→queued, schedule→scheduled)"
```

---

## Task 6: Retire OutputCard / DelegationPhase; rewire AgentService

**Files:**
- Modify: `Sources/MustardKit/Agent/AgentService.swift`
- Modify: `Sources/MustardKit/Models/Recommendation.swift` (remove `OutputCard`)
- Delete: `Sources/MustardKit/Logic/DelegationPhase.swift`, `Tests/MustardTests/DelegationPhaseTests.swift`
- Modify: `Sources/MustardKit/MustardContainer.swift` (drop `OutputCard.self` from the schema)

- [ ] **Step 1: Update `AgentService.decide` to promote via the new plan**

Replace the body that set `.approved`/created tasks/called `execute` with promotion to a board task. For each non-FYI decision, build the task from the rec:

```swift
    public func decide(_ rec: Recommendation, _ decision: RecommendationDecision) {
        rec.decision = decision
        guard decision == .approved || decision == .scheduled || decision == .selfExecute else {
            if decision == .denied, let t = rec.task { t.owner = .me; t.stage = .planned }
            return
        }
        let plan = RecommendationPromotion.plan(action: rec.action, decision: decision)
        let task = rec.task ?? MustardTask(title: rec.title)
        task.notes = rec.draft.isEmpty ? rec.body : rec.draft
        task.owner = plan.owner
        task.stage = plan.stage
        task.actionType = rec.action
        task.confidence = rec.confidence
        task.migratedStage = true
        if task.stage == .scheduled { task.scheduledAt = SchedulingDefaults.tomorrow9() }
        rec.task = task
        task.delegation = rec
        if rec.task == nil { context.insert(task) }
    }
```

(If `SchedulingDefaults.tomorrow9()` doesn't exist, inline the existing `tomorrow9()` helper used by the current Schedule button.)

- [ ] **Step 2: Remove `OutputCard` and its callers**

Delete the `OutputCard` `@Model` from `Recommendation.swift` and remove `accept`/`revise`/`discard`/`execute`'s card creation from `AgentService`. Delegated-task execution result-handling moves to Phase 2/3; for Phase 1, `delegate()` only sets `task.stage = .forAgent`, `task.owner = .agent`:

```swift
    public func delegate(_ task: MustardTask) {
        task.owner = .agent
        task.stage = .forAgent
    }
```

Remove the now-unused `claude`/classify/execute plumbing only if nothing else references it; otherwise leave the runner intact (Phase 3 reuses it) but stop calling it from the board path.

- [ ] **Step 3: Delete `DelegationPhase` + its test; drop OutputCard from schema**

```bash
git rm Sources/MustardKit/Logic/DelegationPhase.swift Tests/MustardTests/DelegationPhaseTests.swift
```
In `MustardContainer.swift` remove `OutputCard.self` from the `Schema([...])` list.

- [ ] **Step 4: Fix all compile errors from removed types**

Run: `swift build` — for each error (views referencing `DelegationPhase`, `OutputCard`, `task.status`), replace with `task.stage`. Repeat until clean.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: PASS (update any tests that referenced removed types/decisions).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(board): retire OutputCard/DelegationPhase; recs promote to board tasks"
```

---

## Task 7: MustardBoardCard view

**Files:**
- Create: `Sources/MustardKit/Views/MustardBoardCard.swift`

Views are verified by `swift build` + Leon's eye (CLAUDE.md). Recreate `MustardBoardCard.dc.html` exactly. Use `Theme` where tokens exist; otherwise the exact hex from the handoff README.

- [ ] **Step 1: Build the card** with this anatomy (top→bottom), driven by a `MustardTask` + `BoardSettings`:
  - Top row: owner toggle (`You` / `✦`, calls `PersonalBoard.reassign`; hidden when `stage == .done`); spacer; `✦ Proposed` pill when the task came from a rec still pending; `🔒`/`lock` SF Symbol when `task.isGated`.
  - Title (`13.5pt`, line-height ~1.35; dimmed + strikethrough when done).
  - Meta row (wrap): area swatch+name, source badge (map `task.source`), due pill (`scheduledAt`) — show only what applies.
  - Confidence (when `settings.showConfidence` and stage is `.needsApproval` or proposed): score + 5 bars; thresholds `≥0.7 #1D9E75`, `≥0.5 #BA7517`, else `#D85A30`; unfilled `#E4DFD5`.
  - Status pill per stage (`forAgent`/`needsApproval`/`queued`/`needsReview` copy + colors per README).
  - Blocked reason row when `stage == .blocked`.
  - Left accent border 2.5px: amber if blocked, else agent-purple if `owner == .agent`.
  - Map the `✦` agent mark to one consistent SF Symbol (e.g. `sparkles`).

- [ ] **Step 2: Add a `#Preview`** using `PreviewData` sample tasks across stages.

- [ ] **Step 3: Build + commit**

Run: `swift build`
```bash
git add Sources/MustardKit/Views/MustardBoardCard.swift
git commit -m "feat(board): MustardBoardCard"
```

---

## Task 8: BoardSettings

**Files:**
- Create: `Sources/MustardKit/Logic/BoardSettings.swift`
- Test: `Tests/MustardTests/BoardSettingsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MustardKit

final class BoardSettingsTests: XCTestCase {
    func test_defaults() {
        let s = BoardSettings(store: UserDefaults(suiteName: "test.board.\(UUID())")!)
        XCTAssertEqual(s.defaultView, .everyone)
        XCTAssertFalse(s.compact)
        XCTAssertTrue(s.showConfidence)
    }
    func test_roundTrips() {
        let store = UserDefaults(suiteName: "test.board.\(UUID())")!
        var s = BoardSettings(store: store); s.defaultView = .agent; s.compact = true; s.showConfidence = false
        let s2 = BoardSettings(store: store)
        XCTAssertEqual(s2.defaultView, .agent); XCTAssertTrue(s2.compact); XCTAssertFalse(s2.showConfidence)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter BoardSettingsTests` → FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct BoardSettings {
    private let store: UserDefaults
    public init(store: UserDefaults = .standard) { self.store = store }

    public var defaultView: BoardOwnerView {
        get { BoardOwnerView(rawValue: store.string(forKey: "board.defaultView") ?? "") ?? .everyone }
        set { store.set(newValue.rawValue, forKey: "board.defaultView") }
    }
    public var compact: Bool {
        get { store.bool(forKey: "board.compact") }
        set { store.set(newValue, forKey: "board.compact") }
    }
    public var showConfidence: Bool {
        get { store.object(forKey: "board.showConfidence") as? Bool ?? true }
        set { store.set(newValue, forKey: "board.showConfidence") }
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter BoardSettingsTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/BoardSettings.swift Tests/MustardTests/BoardSettingsTests.swift
git commit -m "feat(board): BoardSettings (defaultView/density/showConfidence)"
```

---

## Task 9: BoardView rebuild

**Files:**
- Modify: `Sources/MustardKit/Views/BoardView.swift`

Recreate `Mustard - Board.dc.html`. Verified by `swift build` + Leon's eye.

- [ ] **Step 1: Header + controls** — title, "N waiting on you" pill (`PersonalBoard.waitingCount` in current scope, hidden at 0), owner segmented control (`BoardOwnerView`, active `✦ Agent` uses purple `#7F77DD`), area chips, per-view caption. Hold `@State var view` (init from `BoardSettings.defaultView`) and `@State var area: BoardArea`.

- [ ] **Step 2: Columns** — `ForEach(PersonalBoard.columns(for: view))`; each column styled by `stage.kind` per the README color table (background/accent bar/header color); body = `PersonalBoard.tasks(all, in: stage, view: view, area: area)` rendered as `MustardBoardCard`; Done column uses the `doneColumnLimit` + "+N older" footer; empty shows "—"; per-column "+ Add" (stub).

- [ ] **Step 3: Drag** — implement column-to-column drag calling `PersonalBoard.move(task, to: stage)`. Use the existing `uid` for drag identity.

- [ ] **Step 4: Sidebar** — nav (Today/Board/Week/Agent) with agent badge `PersonalBoard.agentBadge(all)`; AREAS rows that set `area` (`Errands`/`Reading` → `.personal`).

- [ ] **Step 5: `@Query` all tasks**, pass to the pure helpers. Search/New task may be stubbed this phase.

- [ ] **Step 6: Build + commit**

Run: `swift build`
```bash
git add Sources/MustardKit/Views/BoardView.swift
git commit -m "feat(board): rebuild BoardView with owner-segmented views"
```

- [ ] **Step 7: Ask Leon to run it and confirm visually** (`./build-app.sh && open build/Mustard.app`). The agent cannot screenshot the native app.

---

## Task 10: Reconcile other views to `stage`

**Files:**
- Modify: `Logic/DayPlanner.swift`, `Logic/WeekPlanner.swift`, `Views/TodayView.swift`, `Views/WeekView.swift`, `Views/HoverPanel.swift`, `Views/NotchSurface.swift`, `Views/AgentConsoleView.swift`

- [ ] **Step 1: Replace `status` reads with `stage`** — e.g. "open" checks use `stage.isOpen`; `inProgress` checks use `stage == .inProgress`; `WeekPlanner.unscheduled` keeps its `owner == .me` filter but switches `scheduledAt == nil` + open via `stage.isOpen`. The agent console's review queue (was `OutputCard`) is removed; its "Review" affordance now points users to the board's Needs Review column.

- [ ] **Step 2: Build** — `swift build` until clean.

- [ ] **Step 3: Run the whole suite** — `swift test`. Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: move Today/Week/Hover/Notch/Console reads to stage"
```

---

## Self-review

**Spec coverage:**
- Owner-segmented views + shared Inbox/Done → Task 1 (`BoardOwnerView.columns`), Task 9.
- 10-stage pipeline, `running` removed, `someday` dropped → Task 1, Task 3.
- Single `stage` source of truth; links/actionType/confidence; `isGated` derived → Task 2.
- status→stage migration incl. scheduledAt-implies-scheduled, agent→queued → Task 3.
- Bucketing + owner/area filters (`personal` = errands ∪ reading) + waiting/badge counts → Task 4.
- Path A (approve→queued / schedule→scheduled) + headless-vs-connector routing → Task 5.
- Path B (delegate→forAgent) → Task 6 (`delegate`).
- Retire OutputCard/DelegationPhase → Task 6.
- Card + board UI per handoff → Tasks 7, 9.
- Settings (defaultView/density/showConfidence) → Task 8.
- Drag = stage change; owner toggle reassignment → Task 4 (logic) + Task 9 (UI).

**Out of scope (correctly absent):** real execution, the file bridge (Phase 2), the worker (Phase 3), Gmail/Xero/Slack/Linear sources, autonomous draft auto-create.

**Placeholder scan:** none — `+ Add`/Search/New task are explicitly stubbed UI affordances, not logic gaps.

**Type consistency:** `TaskStage`, `BoardOwnerView`, `BoardArea`, `TaskLink`, `RecommendationPromotion.Plan` used consistently across tasks; `PersonalBoard.move/reassign/tasks/waitingCount/agentBadge` signatures match between Task 4 definition and Task 9 callers.
