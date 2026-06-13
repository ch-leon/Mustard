# Rich Task Properties Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Mustard's task editor to parity with the Triage-tool's `TaskDrawer` — priority, due date, recurrence, tags, blocked-by, parent/subtasks (keeping estimate) — with the automation behind it (recurrence spawn, subtask cascade-complete, blocked-aware next-up, parent cycle guard).

**Architecture:** Additive SwiftData fields on `MustardTask` (+ two enums) → pure, TDD'd logic units in `Logic/` mirroring the Triage-tool reference (`server/recurrence.ts`, `vault.ts`, `cycleGuard.ts`) → one context-aware completion choke-point → a rebuilt `TaskDetailSheet` + three small reusable Views. Mustard's status enum is unchanged; "blocked" is a derived flag.

**Tech Stack:** Swift / SwiftUI / SwiftData, XCTest. macOS 14+. SPM (`swift build` / `swift test`).

**Spec:** [`docs/task-properties-design.md`](../../task-properties-design.md)

**Conventions (from CLAUDE.md):** Logic is TDD; tests pin a UTC `Calendar` + ISO fixtures; Views are verified by `swift build` + Leon's eye (the dev session can't screenshot the native app). Commit messages: `type(scope): summary` + `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Work stays on branch `feat/rich-task-properties`.

---

## Task 1: Property enums + model fields

**Files:**
- Modify: `Sources/MustardKit/Models/Enums.swift`
- Modify: `Sources/MustardKit/Models/MustardTask.swift`
- Test: `Tests/MustardTests/ModelTests.swift`

- [ ] **Step 1: Write the failing tests** — append to `ModelTests` (inside the class):

```swift
func test_priority_defaultsToNormal_andSurvivesRawRoundTrip() {
    let task = MustardTask(title: "x")
    XCTAssertEqual(task.priority, .normal)
    task.priority = .high
    XCTAssertEqual(task.priorityRaw, "high")
    XCTAssertEqual(task.priority, .high)
}

func test_recurrence_defaultsToNil_andSurvivesRawRoundTrip() {
    let task = MustardTask(title: "x")
    XCTAssertNil(task.recurrence)
    task.recurrence = .weekly
    XCTAssertEqual(task.recurrenceRaw, "weekly")
    XCTAssertEqual(task.recurrence, .weekly)
    task.recurrence = nil
    XCTAssertNil(task.recurrenceRaw)
}

func test_isBlocked_reflectsBlockedReason() {
    let task = MustardTask(title: "x")
    XCTAssertFalse(task.isBlocked)
    task.blockedReason = "waiting on Kamil"
    XCTAssertTrue(task.isBlocked)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter ModelTests`
Expected: FAIL — `value of type 'MustardTask' has no member 'priority'` (etc.).

- [ ] **Step 3: Add the enums** — append to `Sources/MustardKit/Models/Enums.swift`:

```swift
public enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case high, normal, low
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .high: "High"
        case .normal: "Normal"
        case .low: "Low"
        }
    }
}

public enum Recurrence: String, Codable, CaseIterable, Identifiable {
    case daily, weekdays, weekly, monthly
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .daily: "Daily"
        case .weekdays: "Weekdays"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}
```

- [ ] **Step 4: Add the fields + computed accessors** — in `Sources/MustardKit/Models/MustardTask.swift`, add these stored properties after `public var list: TaskList?` (line 16):

```swift
    public var priorityRaw: String = TaskPriority.normal.rawValue
    public var dueAt: Date?
    public var recurrenceRaw: String?
    public var tags: [String] = []
    public var blockedReason: String = ""
    public var recurredFrom: String?
    public var autoCompleted: Bool = false
    public var parent: MustardTask?
    @Relationship(deleteRule: .nullify, inverse: \MustardTask.parent)
    public var subtasks: [MustardTask]? = []
```

Then add these computed accessors next to the existing `status`/`owner` accessors:

```swift
    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    public var recurrence: Recurrence? {
        get { recurrenceRaw.flatMap(Recurrence.init(rawValue:)) }
        set { recurrenceRaw = newValue?.rawValue }
    }

    public var isBlocked: Bool {
        !blockedReason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// (completed, total) over direct subtasks — drives the "0/1" header.
    public var subtaskProgress: (done: Int, total: Int) {
        let subs = subtasks ?? []
        return (subs.filter { $0.status == .done }.count, subs.count)
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ModelTests`
Expected: PASS.

- [ ] **Step 6: Verify the whole suite + build, and confirm migration**

Run: `swift test && swift build`
Expected: 76 tests pass (73 + 3 new), build succeeds.
Then run the app once to confirm the existing on-disk store migrates (additive lightweight migration): `./build-app.sh && open build/Mustard.app`. Expected: app launches, existing tasks intact. (If it crashes on `Could not open Mustard store`, delete `~/Library/Application Support/Mustard/mustard.store` and relaunch — see spec "Migration & risk".)

- [ ] **Step 7: Commit**

```bash
git add Sources/MustardKit/Models/Enums.swift Sources/MustardKit/Models/MustardTask.swift Tests/MustardTests/ModelTests.swift
git commit -m "feat(model): add priority, due, recurrence, tags, blocked-by, parent/subtasks to MustardTask" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Recurrence date math (`RecurrenceEngine.nextDate`)

**Files:**
- Create: `Sources/MustardKit/Logic/RecurrenceEngine.swift`
- Test: `Tests/MustardTests/RecurrenceEngineTests.swift`

- [ ] **Step 1: Write the failing tests** — create `Tests/MustardTests/RecurrenceEngineTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class RecurrenceEngineTests: XCTestCase {
    // Pin UTC so weekday/clamp math is deterministic regardless of machine zone.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func test_daily_addsOneDay() {
        XCTAssertEqual(
            RecurrenceEngine.nextDate(.daily, after: at("2026-06-12T09:00:00Z"), calendar: cal),
            at("2026-06-13T09:00:00Z"))
    }

    func test_weekly_addsSevenDays() {
        XCTAssertEqual(
            RecurrenceEngine.nextDate(.weekly, after: at("2026-06-12T09:00:00Z"), calendar: cal),
            at("2026-06-19T09:00:00Z"))
    }

    func test_weekdays_fridaySkipsToMonday() {
        // 2026-06-12 is a Friday → Monday 2026-06-15
        XCTAssertEqual(
            RecurrenceEngine.nextDate(.weekdays, after: at("2026-06-12T09:00:00Z"), calendar: cal),
            at("2026-06-15T09:00:00Z"))
    }

    func test_weekdays_midweekAddsOneDay() {
        // 2026-06-10 is a Wednesday → Thursday 2026-06-11
        XCTAssertEqual(
            RecurrenceEngine.nextDate(.weekdays, after: at("2026-06-10T09:00:00Z"), calendar: cal),
            at("2026-06-11T09:00:00Z"))
    }

    func test_monthly_clampsToLastValidDay() {
        // Jan 31 + 1 month → Feb 28 (2026 is not a leap year)
        XCTAssertEqual(
            RecurrenceEngine.nextDate(.monthly, after: at("2026-01-31T09:00:00Z"), calendar: cal),
            at("2026-02-28T09:00:00Z"))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter RecurrenceEngineTests`
Expected: FAIL — `cannot find 'RecurrenceEngine' in scope`.

- [ ] **Step 3: Implement `nextDate`** — create `Sources/MustardKit/Logic/RecurrenceEngine.swift`:

```swift
import Foundation

/// Pure recurrence logic, mirroring the Triage-tool's server/recurrence.ts.
public enum RecurrenceEngine {
    /// The next occurrence strictly after `date`, per `rule`.
    public static func nextDate(
        _ rule: Recurrence, after date: Date, calendar: Calendar = .current
    ) -> Date {
        switch rule {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)!
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)!
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: date)!
            while calendar.isDateInWeekend(next) {
                next = calendar.date(byAdding: .day, value: 1, to: next)!
            }
            return next
        case .monthly:
            // Foundation clamps the day to the target month's last valid day.
            return calendar.date(byAdding: .month, value: 1, to: date)!
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RecurrenceEngineTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/RecurrenceEngine.swift Tests/MustardTests/RecurrenceEngineTests.swift
git commit -m "feat(logic): RecurrenceEngine.nextDate (daily/weekly/weekdays/monthly, UTC)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Next recurring instance (`RecurrenceEngine.nextInstance`)

**Files:**
- Modify: `Sources/MustardKit/Logic/RecurrenceEngine.swift`
- Test: `Tests/MustardTests/RecurrenceEngineTests.swift`

- [ ] **Step 1: Write the failing tests** — append to `RecurrenceEngineTests`:

```swift
func test_nextInstance_nilWhenNotRecurring() {
    let t = MustardTask(title: "one-off")
    XCTAssertNil(RecurrenceEngine.nextInstance(of: t, now: at("2026-06-12T09:00:00Z"), calendar: cal))
}

func test_nextInstance_copiesFieldsAndAdvancesDue() {
    let t = MustardTask(title: "standup")
    t.recurrence = .daily
    t.dueAt = at("2026-06-12T00:00:00Z")
    t.priority = .high
    t.tags = ["work"]
    t.estimateMinutes = 15
    let next = RecurrenceEngine.nextInstance(of: t, now: at("2026-06-12T09:00:00Z"), calendar: cal)
    XCTAssertEqual(next?.title, "standup")
    XCTAssertEqual(next?.priority, .high)
    XCTAssertEqual(next?.tags, ["work"])
    XCTAssertEqual(next?.estimateMinutes, 15)
    XCTAssertEqual(next?.recurrence, .daily)
    XCTAssertEqual(next?.dueAt, at("2026-06-13T00:00:00Z"))
    XCTAssertEqual(next?.status, .inbox)
    XCTAssertEqual(next?.recurredFrom, t.uid)
    XCTAssertNil(next?.completedAt)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter RecurrenceEngineTests`
Expected: FAIL — `incorrect argument label` / `no member 'nextInstance'`.

- [ ] **Step 3: Implement `nextInstance`** — add inside `enum RecurrenceEngine`:

```swift
    /// A fresh, un-inserted next instance of a recurring task, or nil if it doesn't
    /// recur. Carries title/notes/priority/tags/owner/list/parent/recurrence; advances
    /// `dueAt` from `dueAt ?? now`; resets status to .inbox; records `recurredFrom`.
    /// The caller inserts the result into a context (see TaskCompletion).
    public static func nextInstance(
        of task: MustardTask, now: Date = .now, calendar: Calendar = .current
    ) -> MustardTask? {
        guard let rule = task.recurrence else { return nil }
        let anchor = task.dueAt ?? now
        let next = MustardTask(title: task.title)
        next.notes = task.notes
        next.priority = task.priority
        next.tags = task.tags
        next.estimateMinutes = task.estimateMinutes
        next.owner = task.owner
        next.list = task.list
        next.parent = task.parent
        next.recurrence = rule
        next.dueAt = nextDate(rule, after: anchor, calendar: calendar)
        next.status = .inbox
        next.recurredFrom = task.uid
        return next
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RecurrenceEngineTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/RecurrenceEngine.swift Tests/MustardTests/RecurrenceEngineTests.swift
git commit -m "feat(logic): RecurrenceEngine.nextInstance spawns the next recurring task" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Parent cycle guard (`TaskHierarchy`)

**Files:**
- Create: `Sources/MustardKit/Logic/TaskHierarchy.swift`
- Test: `Tests/MustardTests/TaskHierarchyTests.swift`

- [ ] **Step 1: Write the failing tests** — create `Tests/MustardTests/TaskHierarchyTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class TaskHierarchyTests: XCTestCase {
    func test_assigningSelfAsParent_isCycle() {
        let t = MustardTask(title: "t")
        XCTAssertTrue(TaskHierarchy.wouldCreateCycle(assigning: t, to: t))
    }

    func test_assigningDescendantAsParent_isCycle() {
        let a = MustardTask(title: "a")
        let b = MustardTask(title: "b"); b.parent = a
        let c = MustardTask(title: "c"); c.parent = b
        // Making a's parent = c would loop a → c → b → a.
        XCTAssertTrue(TaskHierarchy.wouldCreateCycle(assigning: c, to: a))
    }

    func test_assigningUnrelatedParent_isSafe() {
        let a = MustardTask(title: "a")
        let b = MustardTask(title: "b")
        XCTAssertFalse(TaskHierarchy.wouldCreateCycle(assigning: b, to: a))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter TaskHierarchyTests`
Expected: FAIL — `cannot find 'TaskHierarchy' in scope`.

- [ ] **Step 3: Implement** — create `Sources/MustardKit/Logic/TaskHierarchy.swift`:

```swift
import Foundation

/// Pure task-hierarchy guards, mirroring the Triage-tool's server/cycleGuard.ts.
public enum TaskHierarchy {
    /// Would assigning `newParent` as the parent of `task` create a cycle?
    /// True if `newParent` is the task itself, or anywhere up `newParent`'s ancestor
    /// chain we reach `task` (or a pre-existing loop — treated as unsafe).
    public static func wouldCreateCycle(assigning newParent: MustardTask, to task: MustardTask) -> Bool {
        var cursor: MustardTask? = newParent
        var visited = Set<String>()
        while let node = cursor {
            if node === task { return true }
            if visited.contains(node.uid) { return true }
            visited.insert(node.uid)
            cursor = node.parent
        }
        return false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TaskHierarchyTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/TaskHierarchy.swift Tests/MustardTests/TaskHierarchyTests.swift
git commit -m "feat(logic): TaskHierarchy.wouldCreateCycle for the parent picker" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Subtask cascade-complete (`markDone`)

**Files:**
- Modify: `Sources/MustardKit/Models/MustardTask.swift:36-39` (the `markDone` method)
- Test: `Tests/MustardTests/ModelTests.swift`

- [ ] **Step 1: Write the failing tests** — append to `ModelTests`:

```swift
func test_markDone_cascadesToOpenSubtasks_settingAutoCompleted() throws {
    let ctx = try makeContext()
    let parent = MustardTask(title: "parent")
    let c1 = MustardTask(title: "c1")
    let c2 = MustardTask(title: "c2")
    ctx.insert(parent); ctx.insert(c1); ctx.insert(c2)
    c1.parent = parent
    c2.parent = parent
    let when = Date(timeIntervalSince1970: 2_000_000)
    parent.markDone(now: when)
    XCTAssertEqual(parent.status, .done)
    XCTAssertFalse(parent.autoCompleted)        // manually completed
    XCTAssertEqual(c1.status, .done)
    XCTAssertTrue(c1.autoCompleted)             // cascaded
    XCTAssertEqual(c2.status, .done)
}

func test_subtaskProgress_countsDoneOverTotal() throws {
    let ctx = try makeContext()
    let parent = MustardTask(title: "parent")
    let c1 = MustardTask(title: "c1")
    let c2 = MustardTask(title: "c2")
    ctx.insert(parent); ctx.insert(c1); ctx.insert(c2)
    c1.parent = parent; c2.parent = parent
    c1.markDone()
    XCTAssertEqual(parent.subtaskProgress.done, 1)
    XCTAssertEqual(parent.subtaskProgress.total, 2)
}
```

> Note: setting `child.parent = parent` after both are inserted populates `parent.subtasks` via the SwiftData inverse relationship. If a future SwiftData change breaks that in-memory, set `parent.subtasks = [c1, c2]` instead.

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter ModelTests`
Expected: FAIL — `c1.autoCompleted` is `false` (no cascade yet).

- [ ] **Step 3: Implement the cascade** — replace `markDone` in `MustardTask.swift`:

```swift
    /// Mark done, stamping completion time, and cascade-complete open subtasks
    /// (recursively). Idempotent. Subtasks completed this way are flagged
    /// `autoCompleted`; the task you call this on is not.
    public func markDone(now: Date = .now) {
        status = .done
        completedAt = now
        for child in subtasks ?? [] where child.status.isOpen {
            child.autoCompleted = true
            child.markDone(now: now)
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ModelTests`
Expected: PASS.

- [ ] **Step 5: Run the full suite (cascade must not break existing markDone tests)**

Run: `swift test`
Expected: all pass (existing `test_markDone_setsStatusAndCompletedAt`, DayPlanner/PersonalBoard tests still green — a childless task cascades over an empty list).

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Models/MustardTask.swift Tests/MustardTests/ModelTests.swift
git commit -m "feat(model): markDone cascades completion to open subtasks" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Blocked tasks drop out of next-up (`DayPlanner.upcoming`)

**Files:**
- Modify: `Sources/MustardKit/Logic/DayPlanner.swift:24-35` (the `upcoming` method)
- Test: `Tests/MustardTests/DayPlannerTests.swift`

- [ ] **Step 1: Write the failing test** — append to `DayPlannerTests`:

```swift
func test_upcoming_excludesBlockedTasks() {
    let now = at("2026-06-12T10:00:00Z")
    let open = MustardTask(title: "open", scheduledAt: at("2026-06-12T11:00:00Z"))
    let blocked = MustardTask(title: "blocked", scheduledAt: at("2026-06-12T11:30:00Z"))
    blocked.blockedReason = "waiting on review"
    let result = DayPlanner.upcoming([open, blocked], after: now, limit: 5)
    XCTAssertEqual(result.map(\.title), ["open"])
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter DayPlannerTests`
Expected: FAIL — result is `["open", "blocked"]`.

- [ ] **Step 3: Add the `!task.isBlocked` guard** — in `DayPlanner.upcoming`, change the filter line:

```swift
            .filter { task in
                guard task.status.isOpen, !task.isBlocked, let when = task.scheduledAt else { return false }
                return when > after
            }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DayPlannerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/DayPlanner.swift Tests/MustardTests/DayPlannerTests.swift
git commit -m "feat(logic): DayPlanner.upcoming skips blocked tasks" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Completion choke-point (`TaskCompletion`)

**Files:**
- Create: `Sources/MustardKit/Logic/TaskCompletion.swift`
- Test: `Tests/MustardTests/TaskCompletionTests.swift`

- [ ] **Step 1: Write the failing tests** — create `Tests/MustardTests/TaskCompletionTests.swift`:

```swift
import XCTest
import SwiftData
@testable import MustardKit

final class TaskCompletionTests: XCTestCase {
    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, Recommendation.self, OutputCard.self, CalendarEvent.self, configurations: config
        )
        return ModelContext(container)
    }

    func test_complete_nonRecurring_marksDone_noSpawn() throws {
        let ctx = try makeContext()
        let t = MustardTask(title: "one-off")
        ctx.insert(t)
        TaskCompletion.complete(t, in: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MustardTask>()).count, 1)
        XCTAssertEqual(t.status, .done)
    }

    func test_complete_recurring_marksDone_andSpawnsNextInstance() throws {
        let ctx = try makeContext()
        let t = MustardTask(title: "standup")
        t.recurrence = .daily
        t.dueAt = at("2026-06-12T00:00:00Z")
        ctx.insert(t)
        TaskCompletion.complete(t, in: ctx, now: at("2026-06-12T09:00:00Z"))
        let all = try ctx.fetch(FetchDescriptor<MustardTask>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(t.status, .done)
        let spawn = all.first { $0.uid != t.uid }
        XCTAssertEqual(spawn?.recurredFrom, t.uid)
        XCTAssertEqual(spawn?.status, .inbox)
        XCTAssertNil(spawn?.completedAt)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter TaskCompletionTests`
Expected: FAIL — `cannot find 'TaskCompletion' in scope`.

- [ ] **Step 3: Implement** — create `Sources/MustardKit/Logic/TaskCompletion.swift`:

```swift
import Foundation
import SwiftData

/// The single choke-point for the "done" direction: cascade-complete subtasks
/// (via markDone) and, if the task recurs, insert a fresh next instance. Used by
/// every completion path (Today, the detail sheet, Board drag-to-Done) so the
/// automation fires uniformly. Not pure (needs a context); its pieces — markDone
/// and RecurrenceEngine.nextInstance — are unit-tested individually.
public enum TaskCompletion {
    public static func complete(_ task: MustardTask, in context: ModelContext, now: Date = .now) {
        let next = RecurrenceEngine.nextInstance(of: task, now: now)
        task.markDone(now: now)
        if let next { context.insert(next) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TaskCompletionTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Logic/TaskCompletion.swift Tests/MustardTests/TaskCompletionTests.swift
git commit -m "feat(logic): TaskCompletion choke-point (cascade + recurrence spawn)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Route every "done" path through `TaskCompletion`

**Files:**
- Modify: `Sources/MustardKit/Views/TodayView.swift:66-73` (`toggle`)
- Modify: `Sources/MustardKit/Views/TaskDetailSheet.swift:109` (Mark done button)
- Modify: `Sources/MustardKit/Views/BoardView.swift:62-68` (drop handler)

*(Views — verified by build, not XCTest.)*

- [ ] **Step 1: TodayView** — replace `toggle`:

```swift
    private func toggle(_ task: MustardTask) {
        if task.status == .done {
            task.status = .planned
            task.completedAt = nil
        } else {
            TaskCompletion.complete(task, in: context)
        }
    }
```

- [ ] **Step 2: TaskDetailSheet** — replace the Mark done button action (line ~109):

```swift
                Button("Mark done") { TaskCompletion.complete(task, in: context); dismiss() }
                    .buttonStyle(.borderedProminent).tint(Theme.Palette.done).controlSize(.small)
```

- [ ] **Step 3: BoardView** — replace the `dropDestination` body so the done column routes through completion:

```swift
        .dropDestination(for: String.self) { uids, _ in
            guard let uid = uids.first,
                  let task = allTasks.first(where: { $0.uid == uid }) else { return false }
            guard task.status != status else { return true }
            if status == .done {
                TaskCompletion.complete(task, in: context)
            } else {
                PersonalBoard.move(task, to: status)
            }
            return true
        }
```

- [ ] **Step 4: Build + full suite**

Run: `swift build && swift test`
Expected: build succeeds; all tests still pass.

- [ ] **Step 5: Eye check** — `./build-app.sh && open build/Mustard.app`. Confirm: completing a task with a daily recurrence (set one in the detail sheet first — available after Task 10) creates a new instance; completing a parent ticks its subtasks. *(If running before Task 9, verify only that normal completion still works.)*

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Views/TodayView.swift Sources/MustardKit/Views/TaskDetailSheet.swift Sources/MustardKit/Views/BoardView.swift
git commit -m "feat(views): route all completion paths through TaskCompletion" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: New property Views (`PropertyRow`, `TagChipInput`, `ParentPicker`)

**Files:**
- Create: `Sources/MustardKit/Views/PropertyRow.swift`
- Create: `Sources/MustardKit/Views/TagChipInput.swift`
- Create: `Sources/MustardKit/Views/ParentPicker.swift`

*(Views — build + eye.)*

- [ ] **Step 1: PropertyRow** — create `Sources/MustardKit/Views/PropertyRow.swift`:

```swift
import SwiftUI

/// A labelled property row: small uppercase label on the left, control on the right.
/// Mirrors the Triage-tool TaskDrawer's PropertyRow within Mustard's calm styling.
struct PropertyRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 92, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 2: TagChipInput** — create `Sources/MustardKit/Views/TagChipInput.swift`:

```swift
import SwiftUI

/// Editable tag chips backed by a `[String]` binding. Type + Return adds; ✕ removes.
struct TagChipInput: View {
    @Binding var tags: [String]
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag).font(Theme.Fonts.meta)
                    Button {
                        tags.removeAll { $0 == tag }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.textTertiary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.Palette.surface, in: Capsule())
            }
            TextField("+ tag", text: $draft)
                .textFieldStyle(.plain).font(Theme.Fonts.meta)
                .frame(width: 70)
                .onSubmit(add)
        }
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !tags.contains(t) else { draft = ""; return }
        tags.append(t)
        draft = ""
    }
}
```

- [ ] **Step 3: ParentPicker** — create `Sources/MustardKit/Views/ParentPicker.swift`:

```swift
import SwiftUI
import SwiftData

/// Pick a parent task by title. Filters out the task itself and any choice that
/// would create a cycle (TaskHierarchy). Clearing sets parent = nil.
struct ParentPicker: View {
    @Bindable var task: MustardTask
    let candidates: [MustardTask]
    @State private var query = ""

    private var matches: [MustardTask] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return candidates.filter { other in
            other !== task
                && other.title.localizedCaseInsensitiveContains(q)
                && !TaskHierarchy.wouldCreateCycle(assigning: other, to: task)
        }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let parent = task.parent {
                HStack(spacing: 6) {
                    Text(parent.title).font(Theme.Fonts.meta)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Button { task.parent = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.Palette.textTertiary)
                }
            } else {
                TextField("search by title…", text: $query)
                    .textFieldStyle(.plain).font(Theme.Fonts.meta)
                ForEach(matches) { match in
                    Button {
                        task.parent = match
                        query = ""
                    } label: {
                        Text(match.title).font(Theme.Fonts.meta)
                            .foregroundStyle(Theme.Palette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: build succeeds (the new Views compile; not yet referenced).

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Views/PropertyRow.swift Sources/MustardKit/Views/TagChipInput.swift Sources/MustardKit/Views/ParentPicker.swift
git commit -m "feat(views): PropertyRow, TagChipInput, ParentPicker components" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Rebuild `TaskDetailSheet` to the screenshot

**Files:**
- Modify: `Sources/MustardKit/Views/TaskDetailSheet.swift` (replace the body's `ScrollView` content + add a query for parent candidates)

*(View — build + eye. This is the visual parity task; Leon confirms it looks right.)*

- [ ] **Step 1: Add a tasks query + due-date state** — in `TaskDetailSheet`, add after the existing `@State` properties:

```swift
    @Query private var allTasks: [MustardTask]
    @State private var hasDue: Bool
    @State private var dueDate: Date
    @State private var bodyPreview = false
```

And in `init(task:)`, after the existing `_scheduledDate` line:

```swift
        _hasDue = State(initialValue: task.dueAt != nil)
        _dueDate = State(initialValue: task.dueAt ?? Self.defaultSlot())
```

- [ ] **Step 2: Replace the `ScrollView { … }` block** in `body` with the full property set, subtasks, and markdown body:

```swift
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Title") {
                        TextField("Title", text: $task.title)
                            .textFieldStyle(.plain).font(Theme.Fonts.title)
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        PropertyRow(label: "Status") {
                            Picker("", selection: $task.status) {
                                ForEach(TaskStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.labelsHidden().fixedSize()
                        }
                        PropertyRow(label: "Priority") {
                            Picker("", selection: $task.priority) {
                                ForEach(TaskPriority.allCases) { Text($0.label).tag($0) }
                            }.labelsHidden().fixedSize()
                        }
                        PropertyRow(label: "Assignee") {
                            Picker("", selection: $task.owner) {
                                ForEach(TaskOwner.allCases) { Text($0.label).tag($0) }
                            }.labelsHidden().pickerStyle(.segmented).fixedSize()
                        }
                        PropertyRow(label: "Due") {
                            HStack {
                                Toggle("", isOn: $hasDue).labelsHidden().toggleStyle(.switch)
                                    .onChange(of: hasDue) { _, on in task.dueAt = on ? dueDate : nil }
                                if hasDue {
                                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                                        .labelsHidden()
                                        .onChange(of: dueDate) { _, d in task.dueAt = d }
                                }
                            }
                        }
                        PropertyRow(label: "Scheduled") {
                            HStack {
                                Toggle("", isOn: $isScheduled).labelsHidden().toggleStyle(.switch)
                                    .onChange(of: isScheduled) { _, on in
                                        task.scheduledAt = on ? scheduledDate : nil
                                        if on, task.status == .inbox { task.status = .planned }
                                    }
                                if isScheduled {
                                    DatePicker("", selection: $scheduledDate)
                                        .labelsHidden()
                                        .onChange(of: scheduledDate) { _, d in task.scheduledAt = d }
                                }
                            }
                        }
                        PropertyRow(label: "Estimate") {
                            Picker("", selection: $task.estimateMinutes) {
                                ForEach(Self.estimates, id: \.self) { Text("\($0)m").tag($0) }
                            }.labelsHidden().fixedSize()
                        }
                        PropertyRow(label: "Parent") {
                            ParentPicker(task: task, candidates: allTasks)
                        }
                        PropertyRow(label: "Recurrence") {
                            Picker("", selection: Binding(
                                get: { task.recurrence },
                                set: { task.recurrence = $0 }
                            )) {
                                Text("None").tag(Recurrence?.none)
                                ForEach(Recurrence.allCases) { Text($0.label).tag(Recurrence?.some($0)) }
                            }.labelsHidden().fixedSize()
                        }
                        PropertyRow(label: "Tags") {
                            TagChipInput(tags: $task.tags)
                        }
                        PropertyRow(label: "Blocked by") {
                            TextField("reason (optional)", text: $task.blockedReason)
                                .textFieldStyle(.plain).font(Theme.Fonts.meta)
                        }
                    }
                    .padding(14)
                    .background(Theme.Palette.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

                    subtasksSection
                    bodySection
                }
                .padding(20)
            }
```

- [ ] **Step 3: Add `subtasksSection` and `bodySection`** — add these computed properties to `TaskDetailSheet`:

```swift
    private var subtasksSection: some View {
        let progress = task.subtaskProgress
        return VStack(alignment: .leading, spacing: 8) {
            Text("SUBTASKS (\(progress.done)/\(progress.total))")
                .font(.system(size: 10, weight: .semibold)).tracking(0.06)
                .foregroundStyle(Theme.Palette.textTertiary)
            ForEach(task.subtasks ?? []) { sub in
                HStack(spacing: 8) {
                    Image(systemName: sub.status == .done ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(sub.status == .done ? Theme.Palette.done : Theme.Palette.textTertiary)
                    Text(sub.title).font(Theme.Fonts.meta)
                        .strikethrough(sub.status == .done, color: Theme.Palette.textTertiary)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
            }
            Button {
                let child = MustardTask(title: "New subtask")
                child.parent = task
                context.insert(child)
            } label: {
                Label("Add subtask", systemImage: "plus").font(Theme.Fonts.meta)
            }
            .buttonStyle(.plain).foregroundStyle(Theme.Palette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Palette.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BODY").font(.system(size: 10, weight: .semibold)).tracking(0.06)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                Picker("", selection: $bodyPreview) {
                    Text("edit").tag(false)
                    Text("preview").tag(true)
                }.labelsHidden().pickerStyle(.segmented).fixedSize().controlSize(.small)
            }
            if bodyPreview {
                Text(markdownBody)
                    .font(Theme.Fonts.body).foregroundStyle(Theme.Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            } else {
                TextEditor(text: $task.notes)
                    .font(Theme.Fonts.body).frame(minHeight: 90, maxHeight: 220).padding(6)
                    .background(Theme.Palette.bg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Palette.hairline))
            }
        }
    }

    private var markdownBody: AttributedString {
        (try? AttributedString(
            markdown: task.notes,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(task.notes)
    }
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 5: Eye check** — `./build-app.sh && open build/Mustard.app`. Open a task (tap a row in Today or a card on the Board). Confirm against the screenshot: all property rows render and edit; recurrence "None"↔rules; tags add/remove; parent search picks/clears; subtasks list with count; Body edit/preview toggles. **Ask Leon to confirm it looks right** (the dev session can't screenshot the native app).

- [ ] **Step 6: Commit**

```bash
git add Sources/MustardKit/Views/TaskDetailSheet.swift
git commit -m "feat(views): rebuild TaskDetailSheet with full property set, subtasks, markdown body" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 11: Blocked badge on Board + blocked-aware focus

**Files:**
- Modify: `Sources/MustardKit/Views/BoardView.swift` (`BoardCard` — add a blocked badge)
- Modify: `Sources/MustardKit/Views/NotchSurface.swift` (`focusTask` — skip blocked)

*(Views — build + eye.)*

- [ ] **Step 1: Board blocked badge** — in `BoardCard.body`, add after the title `Text(...)`:

```swift
            if task.isBlocked {
                Label("Blocked", systemImage: "exclamationmark.octagon")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
```

- [ ] **Step 2: Blocked-aware notch focus** — in `NotchSurface.swift`, replace `focusTask` (line 115) so a blocked task is never chosen as the focus:

```swift
    private var focusTask: MustardTask? {
        let todays = DayPlanner.tasksForDay(tasks, day: .now).filter { $0.status.isOpen && !$0.isBlocked }
        return tasks.first { $0.status == .inProgress && !$0.isBlocked } ?? todays.first
    }
```

> (The HoverPanel's next-up list already routes through `DayPlanner.upcoming`, fixed in Task 6.)

- [ ] **Step 3: Build + full suite**

Run: `swift build && swift test`
Expected: build succeeds; all tests pass.

- [ ] **Step 4: Eye check** — a task with a blocked-by reason shows a "Blocked" badge on its Board card and is no longer chosen as the notch focus. Ask Leon to confirm.

- [ ] **Step 5: Commit**

```bash
git add Sources/MustardKit/Views/BoardView.swift Sources/MustardKit/Views/NotchSurface.swift
git commit -m "feat(views): blocked badge on Board cards; notch focus skips blocked" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 12: Backlog update

**Files:**
- Modify: `docs/build-order.md`

- [ ] **Step 1: Mark it done + drop the stale item** — add to the "Done ✅" list:

```markdown
- [x] **F13 Rich task properties** — priority, due, recurrence, tags, blocked-by,
      parent/subtasks (+ estimate); recurrence spawn, subtask cascade, blocked-aware
      next-up, cycle guard. See `task-properties-design.md`.
```

And remove the now-superseded `- [ ] Recurrence for tasks.` line from the "Later" section.

- [ ] **Step 2: Commit**

```bash
git add docs/build-order.md
git commit -m "docs: mark rich task properties done in build-order" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `swift test` — expected: **all green** (73 baseline + ~18 new ≈ 91 tests).
- [ ] `swift build` — expected: success.
- [ ] `./build-app.sh && open build/Mustard.app` — Leon's eye check of the rebuilt sheet + automation (recurrence spawn on completing a recurring task; parent completion cascades; blocked badge + focus skip).
- [ ] Use the `superpowers:finishing-a-development-branch` skill to decide merge / PR.

## Notes for the implementer

- **TDD order matters:** Tasks 1–7 are pure logic with real failing tests first. Tasks 8–11 are Views — there are no XCTest assertions for SwiftUI wiring here (per CLAUDE.md), so their gate is `swift build` + Leon's visual confirmation. Don't claim a View "looks right"; state it builds and ask Leon.
- **Migration:** Task 1 is the only schema change. It's additive/optional → lightweight. If the app ever fails to open the store in dev, delete `~/Library/Application Support/Mustard/mustard.store`.
- **Don't widen scope:** no interactive checkboxes in the markdown body, no separate Tag model, no status-enum change — all explicitly out of scope in the spec.
