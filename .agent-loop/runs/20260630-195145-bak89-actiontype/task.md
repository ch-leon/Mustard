# BAK-89 — Task actionType: settable + carried from rec + export guard

**Issue:** https://linear.app/bakinglions/issue/BAK-89 · **Label:** Feature
**Branch:** `leon/bak-89-task-actiontype-settable-export-guard`

## Problem
A task dragged straight to Approved·Queued on the board has no `actionType`, so the
bridge exports an `execute` work order with `actionType=""` — the worker can't tell
what to do. Rec-approved tasks carry it fine (via `promote`).

## Fix (three parts, per Leon's decision)
1. **Export guard (logic, TDD):** `BridgeExport.plan` skips a `.queued` task whose
   `actionType == nil` — it would emit an empty-action execute order. `.forAgent`/prep
   is exempt: an empty action there is expected (prep classifies it). The `actionType`
   getter maps `""`→nil, so the single check covers empty-string raw too.
2. **Settable (UI):** `TaskDetailSheet` gains an "Action" picker — None / Draft email /
   Draft Slack / Shortcut ticket / Update vault (`agentActions`, excludes
   create_task/fyi/ignore which aren't agent-execute outcomes).
3. **Surface the not-filled case (UI):** `MustardBoardCard` shows an amber
   "Needs an action type" status pill on a queued card with no action.

"Carry from rec" already happens (`AgentService.promote` sets `task.actionType =
rec.action`) — no change needed; this issue covers the board-origin path.

### Files
- `Sources/MustardKit/Logic/BridgeExport.swift` — guard in `plan`.
- `Sources/MustardKit/Views/TaskDetailSheet.swift` — Action picker + `agentActions`.
- `Sources/MustardKit/Views/MustardBoardCard.swift` — "Needs an action type" pill.
- `Tests/MustardTests/BridgeExportTests.swift` — 2 new guard tests.

## Acceptance criteria
- [x] actionType settable on a task (detail-sheet picker).
- [x] Carried from rec when task originated from one (pre-existing `promote`).
- [x] Bridge export does NOT emit a queued execute order with empty actionType.
- [x] Not-filled case surfaced (amber card pill) — no silent non-execution.

## Verification note
The two UI changes (picker, pill) are build-verified only — the in-session shell
can't screenshot the native app (CLAUDE.md). Leon confirms visually.
