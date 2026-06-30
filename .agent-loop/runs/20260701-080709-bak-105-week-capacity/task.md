# BAK-105 — Week per-day capacity + load bar + time-of-day grouping

**Run:** 20260701-080709-bak-105-week-capacity · **Milestone:** Redesign · Desktop delta
**Risk class:** medium (Sources/ — WeekPlanner logic + WeekView)

## Done (logic, TDD)
- `WeekPlanner.capacityMinutes(_:on:)` — summed estimate of non-done same-day tasks
  (clock-independent; no overdue coupling so the header bar is stable).
- `WeekPlanner.loadTier(minutes:)` — green ≤360, amber >360, red >480 (overloaded >8h).
- `WeekPlanner.capacityLabel(minutes:)` — "—" / "45m" / "1h" / "1.5h" / "3.5h".
- `WeekPlanner.TimeOfDay` + `timeOfDay(for:)` (Morning<12 / Afternoon<17 / Evening) +
  `groupByTimeOfDay(_:)` (untimed → Anytime; ordered; empty buckets omitted).

## Done (view)
- Day header now shows the **capacity label** (tier-coloured) + a thin **load bar**
  (fill = capacity ÷ 8h, capped), colours per handoff (green doneHead / amber warnText /
  red priorityUrgentBg).
- The day's non-axis tasks are now grouped under **Morning/Afternoon/Evening/Anytime**
  section headers via `groupByTimeOfDay`.

## Architecture note
Desktop keeps its time-axis (8am–6pm) for in-window timed tasks — they're already laid
out by time. The grouping is applied to the below-axis list and is the shared logic the
mobile single-day Week (BAK-116) renders as full sections.
