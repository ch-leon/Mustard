# Morning Ritual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A four-step "Plan your day" wizard (rollover → agent standup → pick today → focus stars) entered from a calm Today banner / notch line / ⌘K, making the day's plan deliberate and the agent standup a daily habit.

**Architecture:** Pure `RitualPlanner` + `RitualPrompt` in Logic/ compute all step content and entry gating; a `MorningRitualView` sheet renders four skippable steps and dispatches only to existing engines (`scheduledAt`/`focusOnDay` mutations, `AgentService.decide`/`snooze`). Two optional stamps on `MustardTask` (`carriedForwardAt`, `focusOnDay`) — no new @Model, no claude calls.

**Tech Stack:** Swift 5.9 SPM, SwiftUI (macOS 14), SwiftData, XCTest. No new dependencies.

**Backing docs:** `docs/specs/2026-07-06-morning-ritual-design.md` (read fully before any task). Tracker: BAK-50. Branch: `claude/morning-ritual` (already created off main).

**Conventions that bind every task (CLAUDE.md):**
- TDD for Logic/: failing test first, run to see it fail, implement, run green. One test file per unit.
- Pin time: `Date(timeIntervalSince1970:)` + `Calendar` with `TimeZone(identifier: "UTC")` injected. Never ambient clock.
- Views: `swift build` only — no view unit tests; never claim views "look right".
- Theme tokens only (`Theme.Palette`/`Theme.Fonts`); mirror TodayView's agent-nudge styling for the banner.
- Commits: `type(scope): summary` + trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Done = full `swift test` (baseline 556, 1 pre-existing skip) + `swift build` green.

**File map:**

| File | Task | Responsibility |
|---|---|---|
| `Sources/MustardKit/Models/MustardTask.swift` (modify) | 1 | `carriedForwardAt`/`focusOnDay` optional stamps |
| `Sources/MustardKit/Logic/DayPlanner.swift` (modify) | 1 | carryForward stamps what it moves |
| `Tests/MustardTests/DayPlannerTests.swift` (extend; create if absent) | 1 | |
| `Sources/MustardKit/Logic/RitualPrompt.swift` (create) + tests | 2 | entry gating |
| `Sources/MustardKit/Logic/RitualPlanner.swift` (create) + tests | 3 | step content + mutations + focus rules |
| `Sources/MustardKit/Logic/NotchTicker.swift` (modify) + tests, `Logic/CommandBarEngine.swift` (modify) + tests | 4 | "Plan your day ✦" idle line; `.planDay` ⌘K |
| `Sources/MustardKit/Views/MorningRitualView.swift` (create) | 5 | the four-step sheet |
| `Sources/MustardKit/Views/TodayView.swift` (modify), `Views/CommandBarView.swift` (modify), notch caller (locate via grep `idleItems`) | 6 | banner, FOCUS pinning, sheet presentation, ⌘K + notch wiring |

Dependencies: 1 → 3 → 5 → 6; 2 and 4 independent after 1.

---

### Task 1: Task stamps + visible carry-forward

**Files:**
- Modify: `Sources/MustardKit/Models/MustardTask.swift` (add two properties near `completedAt`)
- Modify: `Sources/MustardKit/Logic/DayPlanner.swift:107-121` (`carryForward`)
- Test: `Tests/MustardTests/DayPlannerTests.swift` (extend; if the file doesn't exist, create it with this suite)

- [ ] **Step 1: Write the failing test**

```swift
func test_carryForward_stampsMovedTasks_only() {
    let cal = utcCalendar()                       // fixed UTC calendar helper (see below)
    let today = Date(timeIntervalSince1970: 1_751_760_000)   // 2025-07-06T00:00Z-ish; any fixed day
    let stale = MustardTask(title: "old", scheduledAt: today.addingTimeInterval(-86_400))
    let todayTask = MustardTask(title: "today", scheduledAt: today.addingTimeInterval(3_600))
    let unscheduled = MustardTask(title: "loose")

    DayPlanner.carryForward([stale, todayTask, unscheduled], to: today, calendar: cal)

    XCTAssertNotNil(stale.carriedForwardAt)
    XCTAssertTrue(cal.isDate(stale.carriedForwardAt!, inSameDayAs: today))
    XCTAssertNil(todayTask.carriedForwardAt)      // already on today — not moved, not stamped
    XCTAssertNil(unscheduled.carriedForwardAt)
}
```

Use/add the file-local helper:
```swift
private func utcCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}
```
If `DayPlannerTests.swift` doesn't exist, create it with `import XCTest`, `@testable import MustardKit`, `final class DayPlannerTests: XCTestCase { ... }` containing the helper + test. If it exists, match its local conventions.

- [ ] **Step 2: Run** `swift test --filter DayPlannerTests` → FAIL (`carriedForwardAt` undefined).

- [ ] **Step 3: Model fields** in `MustardTask.swift` (near `completedAt`, both defaulted nil — CloudKit-safe, ADR-0001):

```swift
/// Stamped by DayPlanner.carryForward when it moves this task onto a new day —
/// lets the morning ritual show exactly what rolled over (spec 2026-07-06),
/// without changing when/how carry-forward moves tasks. Optional → CloudKit-safe.
public var carriedForwardAt: Date?
/// startOfDay this task is starred as a focus intention for. "Starred today" =
/// focusOnDay is today, so stars expire naturally at midnight — no cleanup pass.
public var focusOnDay: Date?
```

- [ ] **Step 4: Stamp in `carryForward`** — inside the existing loop, after `task.scheduledAt = ...`:

```swift
task.carriedForwardAt = startOfToday
```

- [ ] **Step 5: Run** `swift test --filter DayPlannerTests` → PASS; full `swift test` + `swift build` green.

- [ ] **Step 6: Commit** — `feat(ritual): carriedForwardAt + focusOnDay stamps; carry-forward records what it moved (BAK-50)`

---

### Task 2: `RitualPrompt` gating

**Files:**
- Create: `Sources/MustardKit/Logic/RitualPrompt.swift`
- Create: `Tests/MustardTests/RitualPromptTests.swift`

- [ ] **Step 1: Failing tests** (verbatim; add more if you handle more):

```swift
import XCTest
@testable import MustardKit

final class RitualPromptTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private let now = Date(timeIntervalSince1970: 1_751_790_000)   // mid-day UTC

    func test_neverPlannedNorDismissed_offers() {
        XCTAssertTrue(RitualPrompt.shouldOffer(lastPlannedDay: nil, dismissedDay: nil, now: now, calendar: cal))
    }
    func test_plannedToday_doesNotOffer() {
        XCTAssertFalse(RitualPrompt.shouldOffer(lastPlannedDay: now.addingTimeInterval(-3_600), dismissedDay: nil, now: now, calendar: cal))
    }
    func test_dismissedToday_doesNotOffer() {
        XCTAssertFalse(RitualPrompt.shouldOffer(lastPlannedDay: nil, dismissedDay: now, now: now, calendar: cal))
    }
    func test_plannedYesterday_offersAgain() {
        XCTAssertTrue(RitualPrompt.shouldOffer(lastPlannedDay: now.addingTimeInterval(-86_400), dismissedDay: now.addingTimeInterval(-86_400), now: now, calendar: cal))
    }
}
```

- [ ] **Step 2: Run → FAIL. Step 3: Implement:**

```swift
import Foundation

/// One rule for every morning-ritual entry point (Today banner, notch idle line,
/// ⌘K visibility): offer until the day is planned or the offer is dismissed —
/// both reset at midnight. Pure; state lives in UserDefaults at the call sites.
public enum RitualPrompt {
    public static let lastPlannedKey = "ritualLastPlannedDay"
    public static let dismissedKey = "ritualDismissedDay"

    public static func shouldOffer(
        lastPlannedDay: Date?, dismissedDay: Date?, now: Date, calendar: Calendar = .current
    ) -> Bool {
        let isToday: (Date?) -> Bool = { d in d.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
        return !isToday(lastPlannedDay) && !isToday(dismissedDay)
    }
}
```

- [ ] **Step 4: Run → PASS; full suite. Step 5: Commit** — `feat(ritual): RitualPrompt entry gating (BAK-50)`

---

### Task 3: `RitualPlanner` step content + mutations

**Files:**
- Create: `Sources/MustardKit/Logic/RitualPlanner.swift`
- Create: `Tests/MustardTests/RitualPlannerTests.swift`

API (exact):

```swift
import Foundation

/// Pure content + mutation rules for the four-step morning ritual (spec
/// 2026-07-06). Views render these and dispatch; all decisions live here.
public enum RitualPlanner {
    public static let focusLimit = 3

    /// Step 1 — tasks the silent carry-forward moved onto `day` (open only).
    public static func rollover(_ tasks: [MustardTask], day: Date, calendar: Calendar = .current) -> [MustardTask]

    /// Step 1 mutation — push to the same time tomorrow.
    public static func pushToTomorrow(_ task: MustardTask, calendar: Calendar = .current)
    /// Step 1 mutation — back to the unscheduled inbox.
    public static func sendToInbox(_ task: MustardTask)

    /// Step 3 — unscheduled open tasks (the pick pool). Excludes agent-owned.
    public static func pickCandidates(_ tasks: [MustardTask]) -> [MustardTask]
    /// Step 3 mutation — plan onto `day`, untimed.
    public static func planToday(_ task: MustardTask, day: Date, calendar: Calendar = .current)

    /// Step 3 capacity line — WeekPlanner reuse; nil label when nothing planned.
    public static func capacityLine(_ tasks: [MustardTask], day: Date, calendar: Calendar = .current) -> String?

    /// Step 4 — today's open planned tasks (star candidates), then focus rules.
    public static func focusCandidates(_ tasks: [MustardTask], day: Date, calendar: Calendar = .current) -> [MustardTask]
    public static func focused(_ tasks: [MustardTask], day: Date, calendar: Calendar = .current) -> [MustardTask]
    /// Toggle star; returns false (and does nothing) when adding would exceed focusLimit.
    @discardableResult
    public static func toggleFocus(_ task: MustardTask, in all: [MustardTask], day: Date, calendar: Calendar = .current) -> Bool

    /// Notch focus slot — first open focus task's title (sorted by scheduledAt, then title), nil when none.
    public static func focusTitle(_ tasks: [MustardTask], day: Date, calendar: Calendar = .current) -> String?
}
```

(Step 2's standup content is `RecommendationQueue.pending(recs, now:)` + `AgentInbox.outputCount(tasks)` — already pure and tested; no new logic.)

- [ ] **Step 1: Failing tests:**

```swift
import XCTest
@testable import MustardKit

final class RitualPlannerTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private let day = Date(timeIntervalSince1970: 1_751_760_000)

    private func task(_ title: String, scheduled: Date? = nil) -> MustardTask {
        MustardTask(title: title, scheduledAt: scheduled)
    }

    func test_rollover_onlyOpenTasksStampedToday() {
        let rolled = task("rolled", scheduled: day); rolled.carriedForwardAt = day
        let oldStamp = task("old", scheduled: day); oldStamp.carriedForwardAt = day.addingTimeInterval(-86_400)
        let done = task("done", scheduled: day); done.carriedForwardAt = day; done.stage = .done
        let fresh = task("fresh", scheduled: day)
        XCTAssertEqual(RitualPlanner.rollover([rolled, oldStamp, done, fresh], day: day, calendar: cal).map(\.title), ["rolled"])
    }

    func test_pushToTomorrow_keepsTimeOfDay() {
        let t = task("x", scheduled: day.addingTimeInterval(9 * 3_600))   // 09:00
        RitualPlanner.pushToTomorrow(t, calendar: cal)
        XCTAssertEqual(t.scheduledAt, day.addingTimeInterval(86_400 + 9 * 3_600))
    }

    func test_sendToInbox_clearsSchedule() {
        let t = task("x", scheduled: day)
        RitualPlanner.sendToInbox(t)
        XCTAssertNil(t.scheduledAt)
    }

    func test_pickCandidates_unscheduledOpenMineOnly() {
        let inboxTask = task("pick me")
        let scheduled = task("planned", scheduled: day)
        let done = task("done"); done.stage = .done
        let agents = task("agent's"); agents.owner = .agent
        XCTAssertEqual(RitualPlanner.pickCandidates([inboxTask, scheduled, done, agents]).map(\.title), ["pick me"])
    }

    func test_planToday_setsUntimedToday() {
        let t = task("x")
        RitualPlanner.planToday(t, day: day.addingTimeInterval(13 * 3_600), calendar: cal)
        XCTAssertNotNil(t.scheduledAt)
        XCTAssertTrue(cal.isDate(t.scheduledAt!, inSameDayAs: day))
        XCTAssertFalse(t.isTimed)
    }

    func test_capacityLine_nilWhenNothingPlanned_labelOtherwise() {
        XCTAssertNil(RitualPlanner.capacityLine([task("loose")], day: day, calendar: cal))
        let planned = task("a", scheduled: day)          // default estimate 30m
        XCTAssertEqual(RitualPlanner.capacityLine([planned], day: day, calendar: cal), "30m planned")
    }

    func test_focus_toggleCapsAtThree() {
        let ts = (0..<4).map { i in task("t\(i)", scheduled: day) }
        for t in ts.prefix(3) { XCTAssertTrue(RitualPlanner.toggleFocus(t, in: ts, day: day, calendar: cal)) }
        XCTAssertFalse(RitualPlanner.toggleFocus(ts[3], in: ts, day: day, calendar: cal))   // 4th refused
        XCTAssertEqual(RitualPlanner.focused(ts, day: day, calendar: cal).count, 3)
        XCTAssertTrue(RitualPlanner.toggleFocus(ts[0], in: ts, day: day, calendar: cal))    // un-star works
        XCTAssertEqual(RitualPlanner.focused(ts, day: day, calendar: cal).count, 2)
    }

    func test_focusTitle_firstOpenBySchedule_nilWhenNone() {
        let a = task("later", scheduled: day.addingTimeInterval(10 * 3_600)); a.focusOnDay = day
        let b = task("earlier", scheduled: day.addingTimeInterval(8 * 3_600)); b.focusOnDay = day
        let doneFocus = task("done", scheduled: day); doneFocus.focusOnDay = day; doneFocus.stage = .done
        XCTAssertEqual(RitualPlanner.focusTitle([a, b, doneFocus], day: day, calendar: cal), "earlier")
        XCTAssertNil(RitualPlanner.focusTitle([doneFocus], day: day, calendar: cal))
    }
}
```

- [ ] **Step 2: Run → FAIL. Step 3: Implement** per the API block. Implementation notes:
  - `rollover`: `stage.isOpen` && `carriedForwardAt` non-nil && same day as `day`.
  - `pushToTomorrow`: `scheduledAt = calendar.date(byAdding: .day, value: 1, to: scheduledAt)` (guard non-nil).
  - `pickCandidates`: `scheduledAt == nil && stage.isOpen && owner == .me`.
  - `planToday`: `scheduledAt = calendar.startOfDay(for: day)`, `isTimed = false`.
  - `capacityLine`: open-task count on day == 0 → nil; else `"\(WeekPlanner.capacityLabel(minutes: WeekPlanner.capacityMinutes(tasks, on: day, calendar: calendar))) planned"`.
  - `focusCandidates`: `DayPlanner.tasksForDay` filtered `stage.isOpen`; `focused`: those with `focusOnDay` same-day; `toggleFocus`: un-star always allowed; star only when `focused(...).count < focusLimit`; sets `focusOnDay = calendar.startOfDay(for: day)` / nil.
  - `focusTitle`: `focused` sorted by (`scheduledAt ?? .distantFuture`, then title) → first title.

- [ ] **Step 4: Run → PASS; full suite. Step 5: Commit** — `feat(ritual): RitualPlanner step content + mutations (BAK-50)`

---

### Task 4: Notch line + ⌘K command (pure halves)

**Files:**
- Modify: `Sources/MustardKit/Logic/NotchTicker.swift` + `Tests/MustardTests/NotchTickerTests.swift` (extend)
- Modify: `Sources/MustardKit/Logic/CommandBarEngine.swift` + `Tests/MustardTests/CommandBarEngineTests.swift` (extend)

- [ ] **Step 1: Failing tests:**

```swift
// NotchTickerTests addition
func test_idleItems_planPromptLeadsRotation() {
    let items = NotchTicker.idleItems(focusTitle: "Deep work", waitingCount: 2, planPrompt: true)
    XCTAssertEqual(items.first, "Plan your day ✦")
    XCTAssertTrue(items.contains("Deep work"))
}
func test_idleItems_noPlanPrompt_unchanged() {
    XCTAssertEqual(NotchTicker.idleItems(focusTitle: nil, waitingCount: 0, planPrompt: false), ["All clear"])
}

// CommandBarEngineTests addition
func test_planDayCommand_present() {
    XCTAssertTrue(CommandBarEngine.items(query: "plan").contains { $0.kind == .planDay })
}
```

- [ ] **Step 2: Run → FAIL. Step 3: Implement:**
  - `NotchTicker.idleItems` gains `planPrompt: Bool = false` (defaulted — existing call sites unchanged); when true, insert `"Plan your day ✦"` at position 0 (before the empty-fallback check, so a plan prompt alone yields `["Plan your day ✦"]`).
  - `CommandBarEngine`: `case planDay` in `CommandKind`; item `CommandItem(id: "plan", title: "Plan my day", icon: "sunrise", kind: .planDay)` listed before the go-tos. If an existing test pins the exact unfiltered list, update it faithfully.

- [ ] **Step 4: Run both suites + full suite → green. Step 5: Commit** — `feat(ritual): notch plan-prompt line + ⌘K "Plan my day" (BAK-50 logic)`

---

### Task 5: `MorningRitualView` — the four-step sheet (view-only)

**Files:**
- Create: `Sources/MustardKit/Views/MorningRitualView.swift`

No tests (view). Read first: `Views/TodayView.swift` (nudge styling), `Views/AgentConsoleView.swift` (rec row treatment to echo compactly), `Logic/SourceBadge.swift`, `Logic/SnoozeTargets.swift`, `Logic/Theme.swift`.

- [ ] **Step 1: Build the sheet.** Shape:

```swift
struct MorningRitualView: View {
    let day: Date                                  // captured at open
    let onFinish: () -> Void                       // host stamps lastPlannedDay + dismisses
    let onOpenConsole: () -> Void                  // closes sheet, navigates to Agent tab
    @Environment(AgentService.self) private var agent
    @Environment(\.modelContext) private var context
    @Query private var tasks: [MustardTask]
    @Query private var recs: [Recommendation]
    @State private var step = 0                    // 0...3
}
```

- Frame ~560 wide, min 460 high; `Theme.Palette.bg`; header "Plan your day" (`Theme.Fonts.header`) + date (`Theme.Fonts.body`, textSecondary) + "Step N of 4" (`Theme.Fonts.meta`, textTertiary).
- Progress: 4 segment capsules (filled `Theme.Palette.accent` up to current, else `hairline`); step-name rail (`Theme.Fonts.meta`; current = accent, past = textSecondary, future = textTertiary): "1 Rollover · 2 Agent · 3 Pick · 4 Focus".
- Footer: Back (hidden on step 0) · Spacer · "Skip step" (plain, textTertiary) · Continue (accent-tinted capsule; on step 3 it reads "Start the day" and calls `onFinish`). Skip on step 3 also calls `onFinish` (skipping to the end stamps, per spec).
- **Step 0 Rollover:** rows from `RitualPlanner.rollover(tasks, day: day)` — title (`Theme.Fonts.body`) + three small buttons per row: "Today" (no-op, checkmark state), "Tomorrow" → `RitualPlanner.pushToTomorrow`, "Inbox" → `RitualPlanner.sendToInbox`. Header affordance "Keep all today →" just advances. Empty: "Nothing rolled over — clean slate." (`Theme.Fonts.body`, textTertiary).
- **Step 1 Agent standup:** rows from `RecommendationQueue.pending(recs, now: .now)`: `SourceBadge` chip + confidence (`Theme.Fonts.meta`) + title; buttons Approve (`Task { await agent.decide(rec, .approved) }`), "I'll do it" (`.selfExecute`), Snooze (`agent.snooze(rec, until: SnoozeTargets.nextNineAM(after: .now))`), Reject (`.denied`). Below the list: "N outputs waiting review — Open in console →" (calls `onOpenConsole`) when `AgentInbox.outputCount(tasks) > 0`. Empty: "Nothing from the agent overnight."
- **Step 2 Pick today:** capacity line at top when `RitualPlanner.capacityLine(tasks, day: day)` non-nil (`Theme.Fonts.meta`, textSecondary); list of `RitualPlanner.pickCandidates(tasks)` with a plus button → `RitualPlanner.planToday($0, day: day)`; already-planned-today open tasks shown above with a minus → `RitualPlanner.sendToInbox`. Empty pool: "Inbox is empty."
- **Step 3 Focus:** `RitualPlanner.focusCandidates(tasks, day: day)` rows with star buttons → `RitualPlanner.toggleFocus`; when a star is refused (returns false) show a calm inline hint "Three focus tasks is plenty." (`Theme.Fonts.meta`, `Theme.Palette.warnText`).
- All mutations run on the SwiftData models directly (autosaving main context; matches TodayView's toggle pattern).

- [ ] **Step 2: `swift build` + full `swift test` (556 unchanged... plus Tasks 1–4 additions) → green. Step 3: Commit** — `feat(ritual): MorningRitualView four-step wizard sheet (BAK-50)`

---

### Task 6: Entry points — Today banner, FOCUS pinning, ⌘K + notch wiring (view-only)

**Files:**
- Modify: `Sources/MustardKit/Views/TodayView.swift`
- Modify: `Sources/MustardKit/Views/CommandBarView.swift`
- Modify: the notch caller of `NotchTicker.idleItems` (locate: `grep -rn "idleItems" Sources/`) and, if the plan-prompt state must cross into the notch view, thread it the same way `waitingCount` already flows.

- [ ] **Step 1: TodayView.**
  - State: `@AppStorage(RitualPrompt.lastPlannedKey) private var lastPlanned: Double = 0`, `@AppStorage(RitualPrompt.dismissedKey) private var ritualDismissed: Double = 0`, `@State private var showRitual = false`. Helper: `shouldOffer` = `RitualPrompt.shouldOffer(lastPlannedDay: lastPlanned > 0 ? Date(timeIntervalSince1970: lastPlanned) : nil, dismissedDay: ritualDismissed > 0 ? Date(timeIntervalSince1970: ritualDismissed) : nil, now: .now)`.
  - Banner above `agentNudge`, exact same visual treatment (tint `Theme.Palette.agentTintFaint`… no — this is a YOU action, not agent: use accent-family styling: bg `Theme.Palette.surface`, border `hairline`, sun icon `sunrise` in accent, text "Plan your day — {n} rolled over, {m} from the agent" via `RitualPlanner.rollover(...).count` + `AgentInbox.pendingRecCount(recommendations)`; tap → `showRitual = true`; x-dismiss → `ritualDismissed = Date.now.timeIntervalSince1970`).
  - `.sheet(isPresented: $showRitual) { MorningRitualView(day: today, onFinish: { lastPlanned = Date.now.timeIntervalSince1970; showRitual = false }, onOpenConsole: { showRitual = false; onPlan() }) }` (reuse the existing `onPlan` navigation closure).
  - FOCUS pinning: above the scheduled timeline, when `RitualPlanner.focused(allTasks, day: today)` non-empty, a "FOCUS" section header (same style as "INBOX") listing those tasks via `TimelineRow` with a small `star.fill` accent glyph; they still appear in the timeline (pinning duplicates deliberately — the timeline stays chronological truth). If duplication looks wrong to Leon's eye it's a one-line filter later.
- [ ] **Step 2: CommandBarView** — handle `.planDay`: navigate `screen = .today` and post the sheet. Today owns the sheet state, so the cleanest wire is: CommandBar sets `screen = .today` plus a shared trigger — add `@AppStorage("ritualOpenRequested") private var ritualOpenRequested = false` in both (CommandBarView sets true; TodayView `.onChange` + `onAppear` consumes it → `showRitual = true`, resets false). Comment why (command bar can't reach Today's local state; AppStorage is the app's existing lightweight channel).
- [ ] **Step 3: Notch** — at the `idleItems` call site, pass `planPrompt:` from `RitualPrompt.shouldOffer` (read the two UserDefaults keys directly with `UserDefaults.standard.double(forKey:)`) and prefer `RitualPlanner.focusTitle(tasks, day: .now)` for the `focusTitle:` argument, falling back to its current source. Follow how the caller currently obtains tasks; keep the change minimal.
- [ ] **Step 4: Full `swift test` + `swift build` → green. Step 5: Commit** — `feat(ritual): Today banner + FOCUS pinning + ⌘K/notch entry points (BAK-50)`

---

### Task 7: Finish line

- [ ] Full `swift test` + `swift build` + `./build-app.sh`.
- [ ] Update `CLAUDE.md` folder-layout (RitualPlanner/RitualPrompt in Logic/; MorningRitualView in Views/) and `docs/build-order.md` (mark I5/BAK-50 morning half shipped, evening half deferred).
- [ ] Run artifacts under `.agent-loop/runs/20260706-morning-ritual/` (trace.jsonl, verification.md, risk-report.md, pr-body.md; review-report.md after the fresh-context review).
- [ ] PR to main: `feat(ritual): morning "Plan your day" wizard (BAK-50)`; fresh-context whole-feature review (rubric axes); risk expected MEDIUM (Sources/ only — verify no high-risk paths); merge per policy; digest entry with revert line.
- [ ] Linear: comment + close BAK-50's morning scope (leave a note that evening shutdown is the deferred fast-follow — either keep BAK-50 open rescoped to evening, or close it and file a new backlog issue for the evening flow; prefer the latter: close BAK-50, create "Evening shutdown ritual (fast-follow)" backlog issue linking the spec).

## Self-review notes

- Spec coverage: stamps→T1, gating→T2, step content/mutations/focus/capacity/notch-title→T3, notch line + ⌘K→T4, wizard→T5, banner/pinning/wiring→T6, docs/PR/Linear→T7. Edge behaviors from the spec: never-run (banner-only, T6), rec-decided-mid-ritual (@Query-driven rows, T5), day-flip (day captured at open, T5 prop), capacity-hide (T3 nil rule).
- Type consistency: `RitualPrompt.shouldOffer(lastPlannedDay:dismissedDay:now:calendar:)` used identically in T2/T6/notch; `RitualPlanner` signatures in T3 match every T5/T6 call; `planPrompt:` param name consistent T4/T6.
- Known simplifications vs spec text: capacity "hide when no estimated tasks" resolved to "hide when zero planned open tasks" (estimateMinutes is non-optional, default 30 — a 0-minute misleading state can't occur); recorded here deliberately.
