# BAK-134 — Board "+ New task" + Search

**Run:** 20260701-092926 · **Milestone:** Redesign · Desktop delta · **Risk:** medium (BoardView + PersonalBoard helper)

- **+ New task** header button → inserts an inbox task (owner from the current lens) and opens it in the existing TaskDetailSheet for editing.
- **Search** field in the header → case-insensitive title filter over each column via pure `PersonalBoard.filterBySearch` (TDD).
