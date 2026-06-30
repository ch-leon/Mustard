# BAK-99 — Board card: priority flag, ✦ Proposed pill, tags row

**Run:** 20260701-073543-bak-99-card-meta · **Milestone:** Redesign · Desktop delta
**Risk class:** medium (Sources/ — small additive model change + view)

## Done
- **Model:** added `TaskPriority.urgent` (the handoff card's URGENT flag; enum
  reordered to the handoff form order Low→Urgent, rawValues unchanged) and a derived
  `MustardTask.isProposed` (= agent-owned + inbox).
- **MustardBoardCard:** top row now renders the **priority flag** (HIGH on
  `priorityHighBg`, URGENT on `priorityUrgentBg`) and the **"✦ Proposed" pill** for
  `isProposed` tasks; new **tags row** (`#tag`, max 3) below the meta row. All colours
  from `Theme` (BAK-98 tokens).

## TDD
`BoardCardMetaTests` written first: urgent label, allCases order, isProposed truth
table. 5/5 pass.

## Out of scope
Proposed-state confidence row stays gated to needsApproval (issue scope is the three
meta elements). The create/edit Priority picker auto-gains Urgent via `allCases`.
