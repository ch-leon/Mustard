# BAK-104 — Today: dismissible agent nudge card

**Run:** 20260701-080209-bak-104-nudge · **Milestone:** Redesign · Desktop delta
**Risk class:** medium (Sources/ — shared Logic helper + TodayView + RootView)

## Done
- **`AgentInbox.waitingCount(recommendations:tasks:now:)`** (pure, TDD) = pending
  (un-snoozed, non-ignored) recs via `RecommendationQueue.pending` + needsReview tasks.
- **TodayView nudge:** "Agent has {N} thing(s) for you" card with ✦ avatar, shown when
  count > 0 and not dismissed; tap opens the Agent console (reuses `onPlan`); ✕ dismisses;
  auto-hides when the queue empties.
- **RootView:** refactored `waitingCount` to the shared helper (now also respects
  snooze/ignore — a small correctness improvement to the sidebar badge).

## Notes
`AgentInboxTests` cover pending+review composition, snooze exclusion, empty.
