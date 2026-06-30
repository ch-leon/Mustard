## BAK-104 — Today: dismissible agent nudge

A "Agent has N things for you" nudge on Today, shown when the agent has items waiting (pending recs + needsReview), tap to open the console, ✕ to dismiss, auto-hides when empty.

### Changes
- `AgentInbox.waitingCount(recommendations:tasks:now:)` (pure, TDD) over `RecommendationQueue.pending` + needsReview tasks.
- `TodayView`: dismissible nudge card (reuses `onPlan` to navigate).
- `RootView`: `waitingCount` now uses the shared helper (also respects snooze/ignore).
- `AgentInboxTests` (3).

### Checks
swift build clean · swift test 398 pass / 1 skip / 0 failures (+3).

### Risk
Medium — shared Logic helper + 2 views; no schema/outward. RootView badge now snooze/ignore-aware (improvement).
