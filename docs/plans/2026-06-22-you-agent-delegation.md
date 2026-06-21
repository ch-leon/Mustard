# You → Agent Delegation (I1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let you hand any task to the agent with an explicit "Ask agent to do this" action; the task enters the existing recommend → approve → execute → review loop, closing the currently one-way (agent → you) loop — the core product thesis.

**Architecture:** Delegating fires one `claude -p` *classify* pass (run in the task's client-KB working directory, routed by its Area) that proposes a `Recommendation` (same JSON shape a sweep emits) or **declines**. A new `MustardTask ↔ Recommendation` link ties the proposal back to the task. Trust decides run-now vs queue (delegation runs immediately only at Trusted+; Manual/Supervised queue). Accepting the resulting OutputCard marks the task done and appends the output to the task's Notes. New behaviour goes in PURE, unit-tested units (`Logic/`, `Agent` helpers); `AgentService` gains the orchestration; views only render and dispatch. Two additive optional relationship fields — CloudKit-safe per ADR-0001.

**Tech Stack:** Swift / SwiftUI / SwiftData, XCTest, `swift build` + `swift test`. macOS 14+. SPM package (`MustardKit` lib + `Mustard` exe).

**Locked design:** `docs/build-order.md` (I1, lines ~81–101), plus two implementation decisions confirmed with Leon 2026-06-22: (a) the agent's working directory is **routed by the task's client Area** → that client's KB folder; (b) accepted output is **appended to the task's Notes** (no vault write).

---

## File Structure

**New files:**
- `Sources/MustardKit/Logic/AreaRouter.swift` — pure `Area name → working directory` resolver (reverse of `MeetingTaskSync.defaultAreaMap`, preferring a configured source, else `<workVaultRoot>/<subVault>`).
- `Sources/MustardKit/Logic/DelegationPhase.swift` — pure `DelegationPhase` enum + `resolve(...)` (primitives) + thin `of(_:)` glue for views.
- `Tests/MustardTests/AreaRouterTests.swift`, `DelegationPhaseTests.swift`.

**Modified files:**
- `Sources/MustardKit/Models/MustardTask.swift` — add `delegation: Recommendation?` (`@Relationship`, nullify, inverse `\Recommendation.task`).
- `Sources/MustardKit/Models/Recommendation.swift` — add `task: MustardTask?` (plain, the inverse side).
- `Sources/MustardKit/Logic/TrustPolicy.swift` — add `shouldAutoRunDelegation(actionType:trust:confidence:)`.
- `Sources/MustardKit/Agent/VaultSweep.swift` — add `classifyPrompt(title:notes:areaName:)`.
- `Sources/MustardKit/Agent/AgentService.swift` — add `delegate(_:workVaultRoot:sources:)`, `accept(_:)`, `discard(_:)`; extend `decide` so denying a delegated rec returns the task to you.
- `Sources/MustardKit/Views/TaskDetailSheet.swift` — inject `AgentService`; "Ask agent to do this" footer button.
- `Sources/MustardKit/Views/TimelineRow.swift`, `BoardView.swift`, `WeekView.swift` — context-menu "Ask agent to do this" + delegation status badge.
- `Sources/MustardKit/Views/AgentConsoleView.swift` — route `OutputCardRow` Accept/Discard through `agent.accept/discard`.
- `Tests/MustardTests/AgentTests.swift`, `TrustPolicyTests.swift` — extend.
- `docs/build-order.md` — reconcile (B1 → Done; record I1).

**Commit convention:** `type(scope): summary`, and end every commit message with a second `-m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`. Branch: `feat/you-agent-delegation` (cut before Task 1).

**Verification commands:** `swift test --filter <SuiteName>` per task; `swift build` after view tasks (CLAUDE.md: views are verified by build + eye, not unit tests — never claim a view "looks right"; state it builds and ask Leon to confirm).

---

## Phase 0 — Branch

- [ ] **Step 1: Cut the feature branch**

```bash
git checkout main && git pull
git checkout -b feat/you-agent-delegation
```

---

## Phase 1 — Model link + pure logic

### Task 1: `MustardTask ↔ Recommendation` link

**Files:**
- Modify: `Sources/MustardKit/Models/MustardTask.swift`
- Modify: `Sources/MustardKit/Models/Recommendation.swift`
- Test: `Tests/MustardTests/RecommendationProvenanceTests.swift`

- [ ] **Step 1: Write the failing test**

In `RecommendationProvenanceTests.swift`, add inside the class:

```swift
    func test_taskDelegationLink_roundTrips() throws {
        let ctx = try makeContext()
        let task = MustardTask(title: "Find Ruby's error screens")
        let rec = Recommendation(title: "Locate error screens in Figma", actionType: "vault_note")
        task.delegation = rec
        ctx.insert(task); ctx.insert(rec)
        try ctx.save()

        let savedTask = try ctx.fetch(FetchDescriptor<MustardTask>()).first
        XCTAssertEqual(savedTask?.delegation?.title, "Locate error screens in Figma")
        // Inverse is maintained by SwiftData.
        XCTAssertEqual(rec.task?.title, "Find Ruby's error screens")
    }

    func test_taskDelegation_defaultsNil() {
        XCTAssertNil(MustardTask(title: "x").delegation)
        XCTAssertNil(Recommendation(title: "x").task)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RecommendationProvenanceTests`
Expected: FAIL — `delegation` / `task` are not members.

- [ ] **Step 3: Add the inverse side to `Recommendation`**

In `Recommendation.swift`, after `public var outputs: [OutputCard]? = []` (line ~42):

```swift
    /// The task this recommendation was created to action (set when you delegate a
    /// task to the agent). Nil for sweep/inbox recs. Inverse of `MustardTask.delegation`.
    /// Optional → CloudKit-safe default (ADR-0001).
    public var task: MustardTask?
```

- [ ] **Step 4: Add the owning side to `MustardTask`**

In `MustardTask.swift`, after the `subtasks` relationship (line ~29):

```swift
    /// The agent recommendation produced when this task was delegated ("Ask agent to
    /// do this"). Nullify: deleting the task clears the link but keeps the rec (and its
    /// output history). Optional → CloudKit-safe default (ADR-0001).
    @Relationship(deleteRule: .nullify, inverse: \Recommendation.task)
    public var delegation: Recommendation?
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter RecommendationProvenanceTests`
Expected: PASS. (No `MustardContainer` change — both models are already registered there.)

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Models/MustardTask.swift Sources/MustardKit/Models/Recommendation.swift Tests/MustardTests/RecommendationProvenanceTests.swift
git commit -m "feat(model): link MustardTask to its delegation Recommendation" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `AreaRouter` — route an Area to its KB working directory

**Files:**
- Create: `Sources/MustardKit/Logic/AreaRouter.swift`
- Test: `Tests/MustardTests/AreaRouterTests.swift`

Resolution order: prefer a configured source whose `project` matches the Area's sub-vault folder; else `<workVaultRoot>/<subVault>`; else nil (can't route → caller surfaces a friendly message).

- [ ] **Step 1: Write the failing test**

Create `Tests/MustardTests/AreaRouterTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class AreaRouterTests: XCTestCase {
    // "Digital Licence" → sub-vault "DL" (reverse of MeetingTaskSync.defaultAreaMap).
    func test_derivesFromWorkRoot_whenNoMatchingSource() {
        let dir = AreaRouter.workingDirectory(
            forArea: "Digital Licence", sources: [], workVaultRoot: "/Users/leon/Codeheroes work")
        XCTAssertEqual(dir, "/Users/leon/Codeheroes work/DL")
    }

    func test_prefersConfiguredSource_byProjectFolder() {
        let sources = [SourceConfig(id: .vault, project: "DL", enabled: true,
                                    workingDirectory: "/custom/DL-kb")]
        let dir = AreaRouter.workingDirectory(
            forArea: "Digital Licence", sources: sources, workVaultRoot: "/Users/leon/Codeheroes work")
        XCTAssertEqual(dir, "/custom/DL-kb")
    }

    func test_unknownArea_returnsNil() {
        XCTAssertNil(AreaRouter.workingDirectory(
            forArea: "Personal Errands", sources: [], workVaultRoot: "/Users/leon/Codeheroes work"))
    }

    func test_noWorkRootAndNoSource_returnsNil() {
        XCTAssertNil(AreaRouter.workingDirectory(
            forArea: "Digital Licence", sources: [], workVaultRoot: ""))
    }

    func test_nilArea_returnsNil() {
        XCTAssertNil(AreaRouter.workingDirectory(
            forArea: nil, sources: [], workVaultRoot: "/Users/leon/Codeheroes work"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AreaRouterTests`
Expected: FAIL — no type `AreaRouter`.

- [ ] **Step 3: Implement `AreaRouter`**

Create `Sources/MustardKit/Logic/AreaRouter.swift`:

```swift
import Foundation

/// Pure resolver: a task's client Area → the KB working directory the agent should
/// run `claude -p` in when you delegate that task. Routes by Area (Leon's choice,
/// 2026-06-22) so delegated work runs in-project. Reverses `MeetingTaskSync`'s
/// folder→Area map, prefers an explicitly configured source for that KB, and falls
/// back to `<workVaultRoot>/<subVault>`. Nil when the Area maps to no KB.
public enum AreaRouter {
    public static func workingDirectory(
        forArea areaName: String?,
        sources: [SourceConfig],
        workVaultRoot: String,
        areaMap: [String: String] = MeetingTaskSync.defaultAreaMap
    ) -> String? {
        guard let areaName, !areaName.isEmpty else { return nil }
        // Reverse the folder→Area map: "Digital Licence" → "DL".
        guard let subVault = areaMap.first(where: { $0.value == areaName })?.key else { return nil }

        // Prefer an explicitly configured source for this KB (keeps sweep + delegation
        // running in the same directory for a given project).
        if let configured = sources.first(where: { $0.project == subVault && !$0.workingDirectory.isEmpty }) {
            return configured.workingDirectory
        }

        guard !workVaultRoot.isEmpty else { return nil }
        return URL(fileURLWithPath: workVaultRoot, isDirectory: true)
            .appendingPathComponent(subVault).path
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter AreaRouterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/AreaRouter.swift Tests/MustardTests/AreaRouterTests.swift
git commit -m "feat(logic): AreaRouter maps a task's Area to its KB working directory" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `TrustPolicy.shouldAutoRunDelegation`

Delegation runs immediately only at **Trusted+** (Manual *and* Supervised queue for approval — per the locked design, stricter than sweep auto-run which starts at Supervised). Gated actions never auto-run; confidence floor still applies.

**Files:**
- Modify: `Sources/MustardKit/Logic/TrustPolicy.swift`
- Test: `Tests/MustardTests/TrustPolicyTests.swift`

- [ ] **Step 1: Write the failing test**

In `TrustPolicyTests.swift`, add inside the class:

```swift
    func test_delegation_runsAtTrustedPlus_notSupervised() {
        XCTAssertFalse(TrustPolicy.shouldAutoRunDelegation(actionType: "vault_note", trust: .manual, confidence: 0.9))
        XCTAssertFalse(TrustPolicy.shouldAutoRunDelegation(actionType: "vault_note", trust: .supervised, confidence: 0.9))
        XCTAssertTrue(TrustPolicy.shouldAutoRunDelegation(actionType: "vault_note", trust: .trusted, confidence: 0.9))
        XCTAssertTrue(TrustPolicy.shouldAutoRunDelegation(actionType: "vault_note", trust: .autonomous, confidence: 0.9))
    }

    func test_delegation_gatedNeverAutoRuns() {
        XCTAssertFalse(TrustPolicy.shouldAutoRunDelegation(actionType: "draft_email", trust: .autonomous, confidence: 1.0))
    }

    func test_delegation_respectsConfidenceFloor() {
        XCTAssertFalse(TrustPolicy.shouldAutoRunDelegation(actionType: "vault_note", trust: .trusted, confidence: 0.5))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TrustPolicyTests`
Expected: FAIL — no `shouldAutoRunDelegation`.

- [ ] **Step 3: Implement**

In `TrustPolicy.swift`, after `shouldAutoApprove(...)`:

```swift
    /// May a *delegated* task run immediately (vs. queue for your approval)?
    /// Stricter than `shouldAutoApprove`: delegation only auto-runs at Trusted+ —
    /// Manual and Supervised both queue the proposal. Gated + confidence floor still apply.
    public static func shouldAutoRunDelegation(
        actionType: String, trust: TrustLevel, confidence: Double = 1.0
    ) -> Bool {
        !isGated(actionType: actionType)
            && trust.rank >= TrustLevel.trusted.rank
            && confidence >= autoConfidenceThreshold
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter TrustPolicyTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/TrustPolicy.swift Tests/MustardTests/TrustPolicyTests.swift
git commit -m "feat(logic): TrustPolicy.shouldAutoRunDelegation (Trusted+ runs, else queues)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `DelegationPhase` — the per-task agent status

Pure resolver over primitives so it stays trivially testable; a thin `of(_:)` reads the live task for the views.

**Files:**
- Create: `Sources/MustardKit/Logic/DelegationPhase.swift`
- Test: `Tests/MustardTests/DelegationPhaseTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MustardTests/DelegationPhaseTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class DelegationPhaseTests: XCTestCase {
    func test_notDelegated_isNone() {
        XCTAssertEqual(
            DelegationPhase.resolve(isDelegated: false, executionState: nil,
                                    decision: nil, latestReview: nil, taskDone: false),
            .none)
    }

    func test_queuedForApproval_isProposed() {
        XCTAssertEqual(
            DelegationPhase.resolve(isDelegated: true, executionState: .idle,
                                    decision: .pending, latestReview: nil, taskDone: false),
            .proposed)
    }

    func test_running_isWorking() {
        XCTAssertEqual(
            DelegationPhase.resolve(isDelegated: true, executionState: .running,
                                    decision: .approved, latestReview: nil, taskDone: false),
            .working)
    }

    func test_finishedWithPendingOutput_isAwaitingReview() {
        XCTAssertEqual(
            DelegationPhase.resolve(isDelegated: true, executionState: .finished,
                                    decision: .approved, latestReview: .pending, taskDone: false),
            .awaitingReview)
    }

    func test_taskDone_isDone() {
        XCTAssertEqual(
            DelegationPhase.resolve(isDelegated: true, executionState: .finished,
                                    decision: .approved, latestReview: .accepted, taskDone: true),
            .done)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter DelegationPhaseTests`
Expected: FAIL — no `DelegationPhase`.

- [ ] **Step 3: Implement**

Create `Sources/MustardKit/Logic/DelegationPhase.swift`:

```swift
import Foundation

/// What stage a delegated task is at, derived from its linked Recommendation +
/// latest OutputCard. Drives the row badge ("Agent working…" / "Awaiting review").
public enum DelegationPhase: Equatable {
    case none            // not delegated → no badge
    case proposed        // queued for your approval (Manual/Supervised)
    case working         // claude -p is running
    case awaitingReview  // output produced, waiting for Accept/Revise/Discard
    case done            // accepted → task complete

    public var label: String? {
        switch self {
        case .none: nil
        case .proposed: "Proposed"
        case .working: "Agent working…"
        case .awaitingReview: "Awaiting review"
        case .done: "Done by agent"
        }
    }
}

extension DelegationPhase {
    /// Pure resolver over primitives (testable without a model context).
    public static func resolve(
        isDelegated: Bool, executionState: ExecutionState?,
        decision: RecommendationDecision?, latestReview: ReviewStatus?, taskDone: Bool
    ) -> DelegationPhase {
        guard isDelegated else { return .none }
        if taskDone { return .done }
        if executionState == .running { return .working }
        if latestReview == .pending { return .awaitingReview }
        if decision == .pending { return .proposed }
        // Approved + finished but no pending output (e.g. already reviewed) → no badge.
        return .none
    }

    /// Live-task glue used by the views.
    public static func of(_ task: MustardTask) -> DelegationPhase {
        let rec = task.delegation
        return resolve(
            isDelegated: task.owner == .agent && rec != nil,
            executionState: rec?.executionState,
            decision: rec?.decision,
            latestReview: rec?.outputs?.sorted(by: { $0.createdAt < $1.createdAt }).last?.review,
            taskDone: task.status == .done
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter DelegationPhaseTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/DelegationPhase.swift Tests/MustardTests/DelegationPhaseTests.swift
git commit -m "feat(logic): DelegationPhase derives per-task agent status" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `VaultSweep.classifyPrompt` — the delegate/classify prompt

Reuses `VaultSweep.parse` (returns a `Proposal`); the prompt asks for **exactly one** proposal as a 1-element JSON array, restricts the action set to actionable types, and lets the agent **decline** with `action_type: "ignore"`.

**Files:**
- Modify: `Sources/MustardKit/Agent/VaultSweep.swift`
- Test: `Tests/MustardTests/AgentTests.swift` (in `VaultSweepPromptTests`)

- [ ] **Step 1: Write the failing test**

In `AgentTests.swift`, add inside `VaultSweepPromptTests`:

```swift
    func test_classifyPrompt_includesTaskAndDeclineOption() {
        let p = VaultSweep.classifyPrompt(
            title: "Find Ruby's error screens",
            notes: "Liam asked where they live in Figma.",
            areaName: "Digital Licence")
        XCTAssertTrue(p.contains("Find Ruby's error screens"))
        XCTAssertTrue(p.contains("Liam asked"))
        XCTAssertTrue(p.contains("Digital Licence"))
        XCTAssertTrue(p.contains("\"ignore\""))      // decline path is offered
        XCTAssertTrue(p.contains("JSON array"))       // reuses VaultSweep.parse shape
    }

    func test_classifyPrompt_parsesBackThroughVaultSweepParse() {
        // The shape the prompt asks for must round-trip through the existing parser.
        let modelOutput = #"[{"title":"Locate error screens","body":"Search Figma","action_type":"vault_note","confidence":0.8,"reasoning":"clear ask","draft":"Steps: ..."}]"#
        let proposal = VaultSweep.parse(modelOutput).first
        XCTAssertEqual(proposal?.actionType, "vault_note")
        XCTAssertEqual(proposal?.title, "Locate error screens")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter VaultSweepPromptTests`
Expected: FAIL — no `classifyPrompt`.

- [ ] **Step 3: Implement**

In `VaultSweep.swift`, after `executePrompt(...)` (before the private `directive`):

```swift
    /// Classify prompt for delegation ("Ask agent to do this"): read the task + the
    /// KB in the current directory and propose ONE way to action it — or decline. The
    /// agent never invents work; if the task needs you, it returns action_type "ignore"
    /// with a one-line reason. Output shape matches `parse` (a 1-element JSON array).
    public static func classifyPrompt(title: String, notes: String, areaName: String) -> String {
        """
        You are being asked to take on a task for the knowledge base in the current directory (project: \(areaName)).
        Read the relevant notes, then decide how YOU would action this task.

        Task: \(title)

        \(notes.isEmpty ? "(no extra detail)" : notes)

        Choose ONE action_type: vault_note, draft_email, draft_slack, ticket_write, or ignore.
        Use "ignore" to DECLINE — if this genuinely needs the human (a judgement call, missing
        access, or not something you can do well). Declining honestly is better than faking output.

        Respond with ONLY a JSON array containing exactly ONE object, no prose, in this exact shape:
        [{"title": "short imperative title", "body": "1-2 sentences: what you'll do and why",
          "action_type": "vault_note", "confidence": 0.0-1.0, "reasoning": "one sentence",
          "draft": "your proposed deliverable (or, if ignoring, why this needs the human)"}]
        """
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter VaultSweepPromptTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Agent/VaultSweep.swift Tests/MustardTests/AgentTests.swift
git commit -m "feat(agent): VaultSweep.classifyPrompt for delegation (propose or decline)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 2 — AgentService orchestration

### Task 6: `AgentService.delegate(_:)`

Resolve cwd by Area → classify via `claude -p` → decline path (revert + note) OR create a linked rec → route by trust (Trusted+ runs now; else queue).

**Files:**
- Modify: `Sources/MustardKit/Agent/AgentService.swift`
- Test: `Tests/MustardTests/AgentTests.swift` (in `AgentServiceTests`)

- [ ] **Step 1: Write the failing tests**

In `AgentTests.swift`, add inside `AgentServiceTests`. (These pass explicit `workVaultRoot`/`sources` so they never touch real disk config; the stub `claude` returns canned classify output.)

```swift
    private func delegatableTask(_ ctx: ModelContext, area: String = "Digital Licence") -> MustardTask {
        let a = Area(name: area)
        let list = TaskList(name: area, area: a)
        let task = MustardTask(title: "Find Ruby's error screens")
        task.notes = "Liam asked where they live."
        task.list = list
        ctx.insert(a); ctx.insert(list); ctx.insert(task)
        return task
    }

    func test_delegate_manual_queuesProposal_setsOwnerAgent_noExecute() async throws {
        let ctx = try makeContext()
        var calls = 0
        let service = AgentService(context: ctx, claude: { _, _ in
            calls += 1
            return ClaudeResult(ok: true, text: #"[{"title":"Locate screens","action_type":"vault_note","confidence":0.9,"reasoning":"clear","draft":"steps"}]"#)
        })
        let task = delegatableTask(ctx)

        await service.delegate(task, workVaultRoot: "/work", sources: [])

        XCTAssertEqual(calls, 1)                 // classify ran once; no execute under Manual
        XCTAssertEqual(task.owner, .agent)
        XCTAssertNotNil(task.delegation)
        XCTAssertEqual(task.delegation?.decision, .pending)
        XCTAssertEqual(task.delegation?.vaultPath, "/work/DL")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<OutputCard>()).count, 0)
    }

    func test_delegate_trusted_runsImmediately_producesCard() async throws {
        UserDefaults.standard.set("trusted", forKey: "trustLevel")
        defer { UserDefaults.standard.removeObject(forKey: "trustLevel") }
        let ctx = try makeContext()
        var calls = 0
        let service = AgentService(context: ctx, claude: { _, _ in
            calls += 1
            return ClaudeResult(ok: true, text: #"[{"title":"Locate screens","action_type":"vault_note","confidence":0.9,"reasoning":"clear","draft":"steps"}]"#)
        })
        let task = delegatableTask(ctx)

        await service.delegate(task, workVaultRoot: "/work", sources: [])

        XCTAssertEqual(calls, 2)                 // classify + execute
        XCTAssertEqual(task.delegation?.decision, .approved)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<OutputCard>()).count, 1)
    }

    func test_delegate_decline_revertsOwner_appendsNote_noRec() async throws {
        let ctx = try makeContext()
        let service = AgentService(context: ctx, claude: { _, _ in
            ClaudeResult(ok: true, text: #"[{"title":"x","action_type":"ignore","reasoning":"needs your judgement","draft":"needs your judgement"}]"#)
        })
        let task = delegatableTask(ctx)

        await service.delegate(task, workVaultRoot: "/work", sources: [])

        XCTAssertEqual(task.owner, .me)          // returned to you
        XCTAssertNil(task.delegation)
        XCTAssertTrue(task.notes.contains("needs your judgement"))
    }

    func test_delegate_unresolvedArea_setsError_doesNotChangeOwner() async throws {
        let ctx = try makeContext()
        var calls = 0
        let service = AgentService(context: ctx, claude: { _, _ in calls += 1; return ClaudeResult(ok: true, text: "[]") })
        let task = delegatableTask(ctx, area: "Personal Errands")   // unmapped → no KB

        await service.delegate(task, workVaultRoot: "/work", sources: [])

        XCTAssertEqual(calls, 0)                 // never called claude
        XCTAssertEqual(task.owner, .me)
        XCTAssertNil(task.delegation)
        XCTAssertNotNil(service.lastError)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AgentServiceTests`
Expected: FAIL — no `delegate`.

- [ ] **Step 3: Implement `delegate`**

In `AgentService.swift`, add after `decide(_:_:)`:

```swift
    /// Delegate a task to the agent ("Ask agent to do this"). Routes the agent's
    /// working directory by the task's client Area (Leon's choice, 2026-06-22), runs a
    /// classify pass, and either queues the proposal (Manual/Supervised) or runs it now
    /// (Trusted+). The agent may decline — then the task returns to you with a note.
    /// `workVaultRoot`/`sources` default to live settings; tests inject them.
    public func delegate(
        _ task: MustardTask,
        workVaultRoot: String? = nil,
        sources: [SourceConfig]? = nil
    ) async {
        guard !isSweeping, !isExecuting else { return }
        let root = workVaultRoot ?? UserDefaults.standard.string(forKey: "meetingVaultPath") ?? ""
        let configs = sources ?? SourceSettingsStore.loadOrMigrate().sources
        let areaName = task.list?.area?.name

        guard let cwd = AreaRouter.workingDirectory(
            forArea: areaName, sources: configs, workVaultRoot: root
        ) else {
            lastError = "Can't delegate \"\(task.title)\": file it under a client area (Digital Licence, Sales Buddi, Sandvik, Code Heroes) with a configured KB first."
            return
        }

        lastError = nil
        task.owner = .agent
        let result = await claude(
            VaultSweep.classifyPrompt(title: task.title, notes: task.notes, areaName: areaName ?? ""),
            cwd
        )
        guard result.ok, let proposal = VaultSweep.parse(result.text).first,
              RecommendationAction.from(proposal.actionType) != .ignore else {
            // Decline (or unparseable / failed): return the task to you, with a note.
            task.owner = .me
            let reason = VaultSweep.parse(result.text).first?.draft ?? ""
            task.notes += "\n\n🤖 Agent passed on this" + (reason.isEmpty ? "." : ": \(reason)")
            return
        }

        let rec = Recommendation(
            title: proposal.title, body: proposal.body, actionType: proposal.actionType,
            vaultPath: cwd, confidence: proposal.confidence, reasoning: proposal.reasoning,
            draft: proposal.draft, source: "delegated",
            sourceContext: "Delegated: \(task.title)"
        )
        rec.project = areaName ?? ""
        rec.task = task
        task.delegation = rec
        context.insert(rec)

        let trust = Self.storedTrust()
        if TrustPolicy.shouldAutoRunDelegation(
            actionType: rec.proposedActionType, trust: trust, confidence: rec.confidence
        ) {
            rec.decision = .approved
            let card = await execute(rec)
            if let card, TrustPolicy.shouldAutoAccept(
                actionType: rec.proposedActionType, trust: trust, confidence: rec.confidence
            ) {
                accept(card)
            }
        }
        // else: stays .pending → appears in the Agent console queue for approval.
    }
```

> `accept(_:)` is defined in Task 7; implement Task 7 before running these tests green, or stub `accept` to set `card.review = .accepted` first. To keep commits clean, do Step 4 of Task 7 now if needed.

- [ ] **Step 4: Run the tests** (after Task 7's `accept` exists)

Run: `swift test --filter AgentServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Agent/AgentService.swift Tests/MustardTests/AgentTests.swift
git commit -m "feat(agent): AgentService.delegate — classify, route by Area, gate by trust" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Close the loop — `accept`, `discard`, and deny-returns-to-you

**Files:**
- Modify: `Sources/MustardKit/Agent/AgentService.swift`
- Test: `Tests/MustardTests/AgentTests.swift` (in `AgentServiceTests`)

- [ ] **Step 1: Write the failing tests**

```swift
    func test_accept_delegatedCard_marksTaskDone_appendsOutputToNotes() async throws {
        let ctx = try makeContext()
        let service = AgentService(context: ctx, claude: { _, _ in ClaudeResult(ok: true, text: "x") })
        let task = MustardTask(title: "Write the summary"); task.notes = "context"
        let rec = Recommendation(title: "Write summary", actionType: "vault_note")
        rec.task = task; task.delegation = rec
        let card = OutputCard(content: "Here is the finished summary.", recommendation: rec)
        ctx.insert(task); ctx.insert(rec); ctx.insert(card)

        service.accept(card)

        XCTAssertEqual(card.review, .accepted)
        XCTAssertEqual(task.status, .done)
        XCTAssertNotNil(task.completedAt)
        XCTAssertTrue(task.notes.contains("Here is the finished summary."))
    }

    func test_accept_nonDelegatedCard_justAccepts() throws {
        let ctx = try makeContext()
        let service = AgentService(context: ctx, claude: { _, _ in ClaudeResult(ok: true, text: "x") })
        let rec = Recommendation(title: "Sweep rec", actionType: "vault_note")  // no task link
        let card = OutputCard(content: "done", recommendation: rec)
        ctx.insert(rec); ctx.insert(card)

        service.accept(card)

        XCTAssertEqual(card.review, .accepted)
    }

    func test_discard_delegatedCard_returnsTaskToYou() throws {
        let ctx = try makeContext()
        let service = AgentService(context: ctx, claude: { _, _ in ClaudeResult(ok: true, text: "x") })
        let task = MustardTask(title: "T", owner: .agent)
        let rec = Recommendation(title: "R", actionType: "vault_note")
        rec.task = task; task.delegation = rec
        let card = OutputCard(content: "draft", recommendation: rec)
        ctx.insert(task); ctx.insert(rec); ctx.insert(card)

        service.discard(card)

        XCTAssertEqual(card.review, .discarded)
        XCTAssertEqual(task.owner, .me)
    }

    func test_decide_denyDelegatedRec_returnsTaskToYou() async throws {
        let ctx = try makeContext()
        let service = AgentService(context: ctx, claude: { _, _ in ClaudeResult(ok: true, text: "x") })
        let task = MustardTask(title: "T", owner: .agent)
        let rec = Recommendation(title: "R", actionType: "vault_note")
        rec.task = task; task.delegation = rec
        ctx.insert(task); ctx.insert(rec)

        await service.decide(rec, .denied)

        XCTAssertEqual(task.owner, .me)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AgentServiceTests`
Expected: FAIL — no `accept` / `discard`; `decide(.denied)` doesn't revert owner.

- [ ] **Step 3: Add `accept` and `discard`**

In `AgentService.swift`, after `delegate(...)`:

```swift
    /// Accept an output. For a delegated task this closes the loop: mark the task done
    /// and append the agent's output to its Notes (Leon's choice, 2026-06-22). Non-
    /// delegated cards just flip to accepted (sweep/inbox behaviour unchanged).
    public func accept(_ card: OutputCard) {
        card.review = .accepted
        guard let task = card.recommendation?.task else { return }
        if !card.content.isEmpty {
            task.notes += (task.notes.isEmpty ? "" : "\n\n") + "🤖 Agent output:\n\(card.content)"
        }
        task.markDone()
    }

    /// Discard an output. For a delegated task, hand it back to you.
    public func discard(_ card: OutputCard) {
        card.review = .discarded
        if let task = card.recommendation?.task { task.owner = .me }
    }
```

- [ ] **Step 4: Extend `decide` so denying a delegated rec returns the task**

In `AgentService.swift`, change `decide` — after `rec.decision = decision`, add the deny branch:

```swift
    public func decide(_ rec: Recommendation, _ decision: RecommendationDecision) async {
        rec.decision = decision
        if decision == .denied, let task = rec.task { task.owner = .me }
        guard decision == .approved else { return }
        if rec.action == .fyi { return }
        if rec.action == .createTask { materializeTask(from: rec); return }
        _ = await execute(rec, feedback: rec.comment)
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter AgentServiceTests`
Expected: PASS (including Task 6's tests now that `accept` exists).

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Agent/AgentService.swift Tests/MustardTests/AgentTests.swift
git commit -m "feat(agent): accept closes the delegation loop; deny/discard returns task to you" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 3 — Views (build + eye; no unit tests per CLAUDE.md)

### Task 8: "Ask agent to do this" in the task detail sheet

**Files:**
- Modify: `Sources/MustardKit/Views/TaskDetailSheet.swift`

- [ ] **Step 1: Inject the agent**

At the top of `TaskDetailSheet` (alongside the existing `@Environment`/`@Bindable` at lines ~7–12):

```swift
    @Environment(AgentService.self) private var agent
```

- [ ] **Step 2: Add the button to the footer**

In the `footer` computed property (lines ~163–179), after the "Mark done" button, add a delegate action shown only for your own, not-yet-delegated, open tasks:

```swift
        if task.owner == .me && task.delegation == nil && task.status != .done {
            Button {
                Task { await agent.delegate(task) }
            } label: {
                Label("Ask agent to do this", systemImage: "cpu")
            }
            .tint(Theme.Palette.agent)
            .help("Hand this task to the agent — it proposes how to do it, then runs per your trust level.")
        }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 4: Eye-check + commit**

Run `./build-app.sh && open build/Mustard.app`. Open a task filed under a client area → confirm "Ask agent to do this" appears; clicking it flips the assignee to Agent and (under Manual) a proposal shows in the Agent console. State it builds and runs; ask Leon to confirm the look. Then:

```bash
git add Sources/MustardKit/Views/TaskDetailSheet.swift
git commit -m "feat(ui): Ask-agent-to-do-this action in the task detail sheet" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Context-menu trigger + status badge on rows

**Files:**
- Modify: `Sources/MustardKit/Views/TimelineRow.swift`, `Sources/MustardKit/Views/BoardView.swift`, `Sources/MustardKit/Views/WeekView.swift`

- [ ] **Step 1: Add a shared badge view**

Create the small badge once (put it in `TimelineRow.swift`, above `struct TimelineRow`, so all three files can use it — it's in the same module):

```swift
struct DelegationBadge: View {
    let task: MustardTask
    var body: some View {
        if let label = DelegationPhase.of(task).label {
            Label(label, systemImage: "cpu")
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.agent)
        }
    }
}
```

- [ ] **Step 2: Add the context menu + badge to `TimelineRow`**

Inject the agent at the top of `TimelineRow` (line ~4):

```swift
    @Environment(AgentService.self) private var agent
```

In the meta `HStack` (lines ~42–56), after the existing `if task.owner == .agent { Label("Agent", …) }`, add:

```swift
            DelegationBadge(task: task)
```

After `.onTapGesture(perform: onOpen)` (line ~62), add:

```swift
        .contextMenu {
            if task.owner == .me && task.delegation == nil && task.status != .done {
                Button { Task { await agent.delegate(task) } } label: {
                    Label("Ask agent to do this", systemImage: "cpu")
                }
            }
        }
```

- [ ] **Step 3: Add the same to `BoardView`'s `BoardCard`**

Inject at the top of `BoardCard` (line ~77):

```swift
    @Environment(AgentService.self) private var agent
```

In the card's meta row (lines ~103–116), add `DelegationBadge(task: task)`. After the card's `.overlay(RoundedRectangle…)` (line ~122), add the same `.contextMenu { … }` block from Step 2.

- [ ] **Step 4: Add the same to `WeekView`'s `WeekChip`**

Inject `@Environment(AgentService.self) private var agent` into `WeekChip`; add `DelegationBadge(task: task)` to its metadata row (lines ~250–255); add the `.contextMenu { … }` block to the chip.

- [ ] **Step 5: Build**

Run: `swift build`
Expected: build succeeds. Fix any missing `AgentService` environment (all three rows render inside views that already have `.environment(agent)` from `MustardApp`/`RootView`).

- [ ] **Step 6: Eye-check + commit**

Run the app; right-click a task on Today, Board, and Week → "Ask agent to do this"; confirm a delegated task shows the purple badge cycling Proposed → Agent working… → Awaiting review → Done by agent. State it builds and runs; ask Leon to confirm. Then:

```bash
git add Sources/MustardKit/Views/TimelineRow.swift Sources/MustardKit/Views/BoardView.swift Sources/MustardKit/Views/WeekView.swift
git commit -m "feat(ui): delegate via row context menu + delegation status badge" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: Route console Accept/Discard through the loop-closing methods

So accepting a delegated task's output actually marks the task done + saves notes (and discard returns it to you).

**Files:**
- Modify: `Sources/MustardKit/Views/AgentConsoleView.swift` (`OutputCardRow`, ~481–534)

- [ ] **Step 1: Inject the agent into `OutputCardRow`**

At the top of `OutputCardRow` (near line ~481–483):

```swift
    @Environment(AgentService.self) private var agent
```

- [ ] **Step 2: Route the buttons**

Replace the two direct mutations:

```swift
                Button("Accept") { card.review = .accepted }
```
with:
```swift
                Button("Accept") { agent.accept(card) }
```

and:

```swift
                Button("Discard", role: .destructive) { card.review = .discarded }
```
with:
```swift
                Button("Discard", role: .destructive) { agent.discard(card) }
```

(Leave the existing Revise button as-is — it already calls `agent.revise`.)

- [ ] **Step 3: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 4: Eye-check + commit**

Run the app; delegate a task, let it produce output, hit **Accept** in the console → confirm the source task flips to Done and the output is appended to its Notes (open the task detail). Hit **Discard** on another → confirm the task returns to you (owner Me). State it builds and runs; ask Leon to confirm. Then:

```bash
git add Sources/MustardKit/Views/AgentConsoleView.swift
git commit -m "feat(ui): console Accept/Discard close the delegation loop" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 4 — Docs + final verification

### Task 11: Reconcile build-order.md + full-suite verification

**Files:**
- Modify: `docs/build-order.md`

- [ ] **Step 1: Update the tracker**

In `docs/build-order.md`: move **B1 Meeting task ingest** into the **Done ✅** list as `F17` (it shipped — parser + sync + wiring), and mark **I1** done (or in-progress, per where this lands). Add a one-liner noting the triage-provenance work (#13) and email-scout also landed. Keep the entries terse and consistent with F1–F16.

- [ ] **Step 2: Whole suite green**

Run: `swift test`
Expected: all suites pass (the prior 73 cases + new ones from Tasks 1–7).

- [ ] **Step 3: Build clean**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 4: App smoke test**

Run: `./build-app.sh && open build/Mustard.app`. Verify end-to-end on a client-area task: delegate → (Manual) proposal in console → Approve → output → Accept → task Done + output in Notes; and a Trusted-level delegate runs immediately. Ask Leon to confirm the surfaces.

- [ ] **Step 5: Commit + finish the branch**

```bash
git add docs/build-order.md
git commit -m "docs(build-order): record B1 done + I1 delegation" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

Then use **superpowers:finishing-a-development-branch** to merge/PR.

---

## Self-Review (against the locked design)

- **Trigger = explicit "Ask agent to do this" (detail sheet + Board/Today/Week menu), not the assignee toggle** → Tasks 8, 9. ✅
- **Classify pass via one `claude -p`, proposes a Recommendation, may decline** → Tasks 5, 6. ✅ (decline = `action_type: "ignore"` → owner reverts, note appended.)
- **Assignee flips to `.agent` on delegate, back to `.me` on reject/discard** → Task 6 (set `.agent`); Task 7 (`discard`, `decide(.denied)` → `.me`). ✅
- **Run timing by trust: Manual/Supervised queue; Trusted/Autonomous run now; gated always gated** → Task 3 (`shouldAutoRunDelegation`, Trusted+) + Task 6 routing; gated excluded by `isGated`. ✅
- **Loop close: Accept → task done + output saved to Notes; Revise → existing F15; Reject/Discard → returns to you** → Task 7 (`accept` appends to Notes per Leon's choice) + Task 10 wiring; Revise untouched. ✅
- **Task status: Agent working… → Awaiting review → done, derived from the linked rec** → Task 4 (`DelegationPhase`) + Task 9 badge. ✅
- **New model bit: MustardTask ↔ Recommendation link** → Task 1. ✅
- **cwd routed by client Area (Leon 2026-06-22)** → Task 2 (`AreaRouter`) + Task 6. ✅

**Out of scope (not built here):** sending email/Slack/tickets (still draft-only); a "delegated" `SourceBadge` pill (unknown sources fall back to quiet — fine for v1); multi-step agent plans (I3); diff view (I4); per-Area KB *configuration UI* (routing reads existing `meetingVaultPath` + sources). Note these in the PR so they aren't mistaken for omissions.

## Open item flagged for Leon

- **Area→KB routing depends on `meetingVaultPath` (the `Codeheroes work/` root) being set**, and on tasks being filed under a known client Area. A task in an unmapped Area can't be delegated yet — `delegate` surfaces a clear message rather than guessing. If you want to delegate arbitrary/personal tasks, we'd add a "default delegation KB" setting (small follow-up).
