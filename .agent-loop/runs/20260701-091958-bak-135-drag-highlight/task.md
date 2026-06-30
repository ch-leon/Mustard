# BAK-135 — Board drag-over column highlight

**Run:** 20260701-091958 · **Milestone:** Redesign · Desktop delta · **Risk:** low (view-only)

Added `isTargeted:` to each column's `.dropDestination`; the targeted column shows a
2px accent outline via a `dropTargetStage` @State. Matches the prototype `bcol-drop`.
