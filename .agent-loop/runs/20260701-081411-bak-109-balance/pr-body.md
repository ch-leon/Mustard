## BAK-109 — Week ✦ Balance + Undo

Adds the agent "✦ Balance" action that flattens the week's overloaded days, with an exact Undo.

### Changes (logic, TDD)
- `WeekPlanner.balance(_:weekdays:)` — greedy LPT bin-packing of movable (non-done) tasks across Mon–Fri into the least-loaded day (ties keep current day); returns `BalancePlan { moves, peakMinutes }`, each move carrying its prior `scheduledAt` for Undo. Excludes done; preserves time-of-day.

### Changes (view)
- WeekView "✦ Balance" header button → applies + dark toast ("moved N, peak now Xh") with Undo, or "already balanced"; auto-dismiss 6s.

### Checks
swift build clean · swift test 407 pass / 1 skip / 0 failures (+4).

### Risk
Medium — pure algorithm + view; mutation fully reversible via the Undo snapshot; no schema/outward.
