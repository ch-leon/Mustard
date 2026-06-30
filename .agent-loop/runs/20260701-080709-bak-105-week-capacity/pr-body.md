## BAK-105 — Week per-day capacity + load bar + time-of-day grouping

Adds per-day capacity (summed estimate of non-done tasks) with a tier-coloured load bar, and groups the day's non-axis tasks under Morning/Afternoon/Evening/Anytime.

### Changes (logic, TDD)
- `WeekPlanner.capacityMinutes(_:on:)`, `loadTier(minutes:)` (green ≤6h / amber >6h / red >8h), `capacityLabel(minutes:)`, `TimeOfDay` + `timeOfDay(for:)` + `groupByTimeOfDay(_:)`.

### Changes (view)
- WeekView day header: capacity label (tier-coloured) + thin load bar (fill = capacity ÷ 8h).
- Non-axis day tasks grouped under time-of-day section headers.

### Architecture
Desktop keeps its 8am–6pm time-axis for in-window timed tasks; grouping is the shared logic mobile's single-day Week (BAK-116) will render as full sections.

### Checks
swift build clean · swift test 403 pass / 1 skip / 0 failures (+5).

### Risk
Medium — pure logic + view; no schema/outward.
