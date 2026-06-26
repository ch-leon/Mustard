# Ownership Badge (needs-me vs agent) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich the per-task delegation badge so every row instantly reads "needs me" (amber) vs "the agent has it" (purple), and fold the two redundant owner indicators into that single badge.

**Architecture:** The *decision* (phase → visual tone, plus the label rename) is a pure, unit-tested addition to `DelegationPhase` in `Logic/`. Two amber design tokens go in `Theme`. The `DelegationBadge` view (defined in `TimelineRow.swift`, shared by Board + Week) maps tone → style and gains a fallback for agent-owned-without-phase; the now-redundant owner indicators are deleted from `TimelineRow` and `WeekChip`. `BoardCard` already shows only the badge, so it upgrades for free. **No model change, no migration.**

**Tech Stack:** Swift / SwiftUI / SwiftData, XCTest, `swift build` + `swift test`. macOS 14+. SPM package (`MustardKit` lib + `Mustard` exe).

**Locked design:** `docs/specs/2026-06-26-ownership-badge-design.md` (approved 2026-06-26). Direction A — one badge, two weights; `proposed` + `awaitingReview` = amber "needs you"; `working` = purple; `done` = grey; `awaitingReview` relabelled "Your turn".

**Branch:** `feat/ownership-badge` is already cut from current `main`, with the spec + research committed. **No Phase-0 branch step.**

---

## File Structure

**New files:** none.

**Modified files:**
- `Sources/MustardKit/Logic/DelegationPhase.swift` — add `DelegationTone` enum + `DelegationPhase.tone`; rename the `.awaitingReview` label to "Your turn".
- `Sources/MustardKit/Logic/Theme.swift` — add `warningSoft` + `warningDeep` palette tokens.
- `Sources/MustardKit/Views/TimelineRow.swift` — rework `DelegationBadge` (tone → treatment + fallback); delete the standalone `Label("Agent")`.
- `Sources/MustardKit/Views/WeekView.swift` — delete the redundant leading `cpu` icon in `WeekChip`.
- `Tests/MustardTests/DelegationPhaseTests.swift` — add `tone` + label tests.

**Unchanged (inherits the upgraded badge):** `Sources/MustardKit/Views/BoardView.swift` (`BoardCard` already renders only `DelegationBadge`).

**Commit convention:** `type(scope): summary`, and end every commit with a second `-m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`.

**Verification commands:** `swift test --filter DelegationPhaseTests` (Task 1); `swift build` after each view task; `swift test` (whole suite) + `./build-app.sh && open build/Mustard.app` at the end. Per CLAUDE.md, views are verified by build + eye — never claim a view "looks right"; state it builds and ask Leon to confirm.

---

## Phase 1 — Logic (TDD)

### Task 1: `DelegationTone` + `DelegationPhase.tone` + "Your turn" label

**Files:**
- Modify: `Sources/MustardKit/Logic/DelegationPhase.swift`
- Test: `Tests/MustardTests/DelegationPhaseTests.swift`

- [ ] **Step 1: Write the failing tests**

In `DelegationPhaseTests.swift`, add inside the class (after the existing `test_taskDone_isDone`):

```swift
    func test_tone_none_isNil() {
        XCTAssertNil(DelegationPhase.none.tone)
    }

    func test_tone_proposedAndAwaitingReview_areNeedsYou() {
        XCTAssertEqual(DelegationPhase.proposed.tone, .needsYou)
        XCTAssertEqual(DelegationPhase.awaitingReview.tone, .needsYou)
    }

    func test_tone_working_isAgentHasIt() {
        XCTAssertEqual(DelegationPhase.working.tone, .agentHasIt)
    }

    func test_tone_done_isDoneByAgent() {
        XCTAssertEqual(DelegationPhase.done.tone, .doneByAgent)
    }

    func test_awaitingReviewLabel_isYourTurn() {
        XCTAssertEqual(DelegationPhase.awaitingReview.label, "Your turn")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DelegationPhaseTests`
Expected: FAIL — `tone` is not a member of `DelegationPhase`; and `test_awaitingReviewLabel_isYourTurn` fails on the old "Awaiting review" string.

- [ ] **Step 3: Add the `DelegationTone` enum**

In `DelegationPhase.swift`, immediately after `import Foundation` (line 1) and before `public enum DelegationPhase`:

```swift
/// The visual weight a delegation badge carries on a row.
/// agentHasIt = calm purple (ignore); needsYou = amber (your move); doneByAgent = quiet grey.
public enum DelegationTone: Equatable { case agentHasIt, needsYou, doneByAgent }
```

- [ ] **Step 4: Rename the `awaitingReview` label**

In the `label` computed property, change:

```swift
        case .awaitingReview: "Awaiting review"
```
to:
```swift
        case .awaitingReview: "Your turn"
```

- [ ] **Step 5: Add the `tone` property**

In the `DelegationPhase` enum body, directly after the `label` computed property's closing brace, add:

```swift
    /// Visual weight for the row badge. nil ⇒ no badge.
    /// proposed + awaitingReview both put the ball in your court → needsYou.
    public var tone: DelegationTone? {
        switch self {
        case .none: nil
        case .proposed, .awaitingReview: .needsYou
        case .working: .agentHasIt
        case .done: .doneByAgent
        }
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter DelegationPhaseTests`
Expected: PASS (the 5 new cases + the 5 existing `resolve` cases).

- [ ] **Step 7: Commit**

```bash
git add Sources/MustardKit/Logic/DelegationPhase.swift Tests/MustardTests/DelegationPhaseTests.swift
git commit -m "feat(logic): DelegationPhase.tone + 'Your turn' label for the ownership badge" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 2 — Design tokens

### Task 2: amber "needs-you" tokens in `Theme`

No unit test (pure colour constants); verified by `swift build` + the view tasks that consume them.

**Files:**
- Modify: `Sources/MustardKit/Logic/Theme.swift`

- [ ] **Step 1: Add the two tokens**

In `Theme.Palette`, immediately after the `warning` token (line ~30):

```swift
        public static let warningSoft = Color(hex: "#FAEEDA") // amber pill background (needs-you badge)
        public static let warningDeep = Color(hex: "#633806") // amber pill text (needs-you badge)
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds (tokens compile; not yet used).

- [ ] **Step 3: Commit**

```bash
git add Sources/MustardKit/Logic/Theme.swift
git commit -m "feat(theme): amber needs-you tokens (warningSoft/warningDeep)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 3 — Views (build + eye; no unit tests per CLAUDE.md)

### Task 3: two-weight `DelegationBadge`; drop the standalone `Label("Agent")`

`DelegationBadge` lives at the top of `TimelineRow.swift` and is reused by Board + Week, so this task upgrades all three surfaces. It also removes TimelineRow's own redundant owner label.

**Files:**
- Modify: `Sources/MustardKit/Views/TimelineRow.swift`

- [ ] **Step 1: Replace the `DelegationBadge` struct**

Replace the entire current struct (lines ~3–12):

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

with:

```swift
struct DelegationBadge: View {
    let task: MustardTask
    var body: some View {
        let phase = DelegationPhase.of(task)
        if let label = phase.label, let tone = phase.tone {
            content(label, tone)
        } else if task.owner == .agent {
            content("Agent", .agentHasIt)   // agent-owned, no active phase
        }
    }

    @ViewBuilder private func content(_ label: String, _ tone: DelegationTone) -> some View {
        switch tone {
        case .agentHasIt:
            Label(label, systemImage: "cpu")
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.agent)
        case .needsYou:
            Label(label, systemImage: "cpu")
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.warningDeep)
                .padding(.vertical, 1).padding(.horizontal, 8)
                .background(Theme.Palette.warningSoft, in: Capsule())
        case .doneByAgent:
            Label(label, systemImage: "checkmark")
                .font(Theme.Fonts.meta)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
```

- [ ] **Step 2: Delete the standalone `Label("Agent")` in `TimelineRow.body`**

In the meta `HStack` (lines ~54–67), delete this block (the `DelegationBadge(task: task)` line directly below it stays):

```swift
                        if task.owner == .agent {
                            Label("Agent", systemImage: "cpu")
                                .foregroundStyle(Theme.Palette.agent)
                        }
```

Leave the enclosing condition `if task.estimateMinutes != 30 || task.owner == .agent || task.list != nil { … }` untouched — keeping `task.owner == .agent` there ensures the meta row (and thus the badge) still shows for an agent-owned task with no list/estimate.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 4: Eye-check + commit**

Run `./build-app.sh && open build/Mustard.app`. On **Today**: delegate a client-area task and confirm one badge cycles **Proposed (amber pill) → Agent working… (purple) → Your turn (amber pill) → Done by agent (grey ✓)**; confirm there is no longer a duplicate `⚙ Agent` next to it; confirm a task you own shows no badge. (Board cards upgrade automatically — sanity-check one there too.) State it builds and runs; ask Leon to confirm the look. Then:

```bash
git add Sources/MustardKit/Views/TimelineRow.swift
git commit -m "feat(ui): two-weight DelegationBadge; drop redundant Agent label (TimelineRow)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: drop the redundant leading `cpu` icon in `WeekChip`

**Files:**
- Modify: `Sources/MustardKit/Views/WeekView.swift`

- [ ] **Step 1: Delete the leading icon**

In `WeekChip.body` (lines ~253–256), delete this block (the trailing `DelegationBadge(task: task)` at line ~259 stays and now carries the agent signal):

```swift
            if task.owner == .agent {
                Image(systemName: "cpu").font(.system(size: 10)).foregroundStyle(Theme.Palette.agent)
            }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Eye-check + commit**

Run the app; on **Week**, confirm a delegated chip shows a single trailing badge (no leading `⚙`), and the amber "Your turn" pill is legible at chip size. State it builds and runs; ask Leon to confirm. Then:

```bash
git add Sources/MustardKit/Views/WeekView.swift
git commit -m "feat(ui): drop redundant leading cpu icon in WeekChip" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 4 — Verify + finish

### Task 5: whole-suite verification + branch finish

**Files:**
- (Optional) Modify: `docs/build-order.md`

- [ ] **Step 1: Whole suite green**

Run: `swift test`
Expected: all suites pass (existing cases + the 5 new `DelegationPhaseTests`).

- [ ] **Step 2: Build clean**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: App smoke test across surfaces**

Run: `./build-app.sh && open build/Mustard.app`. Verify Today, Board, and Week all show the single two-weight badge with no duplicate owner indicators, and your own tasks stay bare. Ask Leon to confirm the surfaces.

- [ ] **Step 4 (optional): Note it in the tracker**

If `docs/build-order.md` has a natural slot, add a one-line entry recording the ownership-badge enhancement (consistent with existing entries). Then:

```bash
git add docs/build-order.md
git commit -m "docs(build-order): record ownership-badge enhancement" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: Finish the branch**

Use **superpowers:finishing-a-development-branch** to open the PR (HTTPS origin `ch-leon/Mustard` — never push over SSH).

---

## Self-Review (against the spec)

- **One badge is the sole owner signal** (spec Decision 1) → Task 3 (rework + fallback) + Task 3/4 (delete the two redundant indicators). ✅
- **Badge only when agent-involved; own tasks bare** (Decision 2) → `DelegationBadge` renders nothing unless a phase exists or `owner == .agent`; TimelineRow meta condition unchanged. ✅
- **Pure `DelegationTone` decision** (Decision 3) → Task 1, unit-tested. ✅
- **Tone mapping** proposed+awaitingReview=needsYou / working=agentHasIt / done=doneByAgent (Decision 4) → Task 1 `tone` + tests. ✅
- **Rename awaitingReview → "Your turn"** (Decision 5) → Task 1 Step 4 + `test_awaitingReviewLabel_isYourTurn`. ✅
- **Agent-owned-no-phase fallback** (Decision 6) → Task 3 `else if task.owner == .agent`. ✅
- **Two amber tokens** (Decision 7) → Task 2; consumed in Task 3's `needsYou` case. ✅

**Type consistency:** `DelegationTone` cases (`agentHasIt`/`needsYou`/`doneByAgent`) are identical across Task 1 (definition + tests) and Task 3 (`content(_:_:)` switch). `Theme.Palette.warningSoft`/`warningDeep` defined in Task 2, used in Task 3. No mismatches.

**Out of scope (not built here):** notch waiting-count tinting; agent-returned/declined task badges; priority/provenance on rows; multi-agent "Delegated to X". Flag in the PR so they aren't read as omissions.
