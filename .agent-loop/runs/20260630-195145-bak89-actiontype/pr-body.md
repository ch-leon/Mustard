## BAK-89 — Task actionType: settable + carried from rec + export guard

A task dragged straight to **Approved·Queued** on the board had no `actionType`, so the bridge exported an `execute` work order with `actionType=""` — the connected-session worker couldn't tell what to do. (Rec-approved tasks carry it fine via `promote`.)

### Changes
- **Export guard** (`BridgeExport.plan`) — skips a `.queued` task with no `actionType` (would emit an empty-action execute order). `.forAgent`/prep is exempt: an empty action there is expected — classifying it is exactly what the prep pass does. The `actionType` getter maps `""`→nil, so the single `== nil` check covers the empty-string raw too.
- **Settable** (`TaskDetailSheet`) — an "Action" picker: None / Draft email / Draft Slack / Shortcut ticket / Update vault (`agentActions` excludes create_task/fyi/ignore, which aren't agent-execute outcomes).
- **Surface** (`MustardBoardCard`) — a queued card with no action shows an amber **"Needs an action type"** pill, so it's visibly not-runnable until set.

"Carry from rec" already happens (`AgentService.promote` sets `task.actionType = rec.action`) — no change needed; this covers the board-origin path.

### Tests (TDD, red→green)
- `test_queuedTask_withoutActionType_isSkipped` — the guard.
- `test_forAgentTask_withoutActionType_stillWritesPrep` — prep stays exempt.
- `test_queuedNoAction_withLiveOutbox_neitherWritesNorCancels` — guards the no-action skip vs BAK-92's stale-outbox cancel logic (review follow-up).

### Checks
- `swift test` → 348 pass / 1 skip (+3 tests)
- `swift build` → clean (executable links — views compile)

### Risk
Medium (`Feature`; Sources/Logic + Views; no high path, no AgentService change) → auto-merge after fresh-context review. No irreversible outward action.

### Review
Fresh-context review: **APPROVE, no blockers.** Its actionable follow-up (lock the no-action-vs-stale-outbox interaction) is in commit `e9ff97e`.

### Note for Leon (UI — build-verified only)
The Action picker and the amber pill compile but can't be screenshotted in-session (CLAUDE.md). Please eyeball: detail-sheet Action picker persists the choice; a queued card flips amber "Needs an action type" → "Queued to run" once an action is set.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
