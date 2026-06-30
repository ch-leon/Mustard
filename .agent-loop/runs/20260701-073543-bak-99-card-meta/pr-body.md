## BAK-99 — Board card: priority flag, ✦ Proposed pill, tags row

Adds the three missing top-of-card elements from the handoff.

### Changes
- **Model:** `TaskPriority.urgent` (handoff URGENT flag; enum reordered to form order Low→Urgent, rawValues stable → no migration); derived `MustardTask.isProposed` (agent-owned + inbox).
- **MustardBoardCard:** top row renders priority flag (HIGH/URGENT) + "✦ Proposed" pill; new tags row (#tag, max 3). All colours from `Theme`.
- **Tests:** `BoardCardMetaTests` (TDD) — urgent label, allCases order, isProposed truth table.

### Checks
- `swift build` clean · `swift test` 382 pass / 1 skip / 0 failures (+5).

### Risk
Medium — additive model + view; no auth/trust/ClaudeRunner; no schema migration.
