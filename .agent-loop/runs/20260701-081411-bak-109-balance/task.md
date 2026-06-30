# BAK-109 — Week ✦ Balance (redistribute + Undo)

**Run:** 20260701-081411-bak-109-balance · **Milestone:** Redesign · Desktop delta
**Risk class:** medium (Sources/ — WeekPlanner algorithm + WeekView)
**Blocked-by:** BAK-105 (capacity/label) — done.

## Done (logic, TDD)
- `WeekPlanner.balance(_:weekdays:)` — greedy LPT: movable (non-done) tasks scheduled
  within the weekdays are packed largest-first into the least-loaded day; ties keep the
  task on its current day (minimal churn). Returns `BalancePlan { moves, peakMinutes }`
  where each `BalanceMove` carries the prior `scheduledAt` for an exact Undo. Meetings
  (calendar events) and done tasks are never moved. Move preserves time-of-day.

## Done (view)
- Header **"✦ Balance"** button → applies the plan (Mon–Fri), shows a dark toast
  "Balanced your week · moved N task(s), peak day now Xh" with an **Undo** (restores each
  task's prior date), or "Your week is already balanced" when nothing moves. Toast
  auto-dismisses after 6s.

## Notes
`WeekBalanceTests` (pinned UTC): flatten, already-balanced (0 moves), done-excluded,
time-of-day preserved on move.
