# BAK-102 — Board column polish (auto-collapse empties + Drop here)

**Run:** 20260701-075244-bak-102-column-polish · **Milestone:** Redesign · Desktop delta
**Risk class:** medium (Sources/ — BoardView + PersonalBoard helper)

## Done
- **Auto-collapse empty columns** to a ~40px vertical strip (rotated UPPERCASE label +
  "0"), **Everyone lens only**, not while review-focused, tap to expand (remembered in
  `expandedEmpty`). Rule lives in pure `PersonalBoard.shouldCollapseEmpty(...)` (TDD).
- Empty (expanded) columns now read **"Drop here"** instead of "—".

## Already present (not rebuilt)
- Per-column **"+ Add"** is the existing `QuickColumnAdd` (used per column).

## Notes
`BoardFocusTests` extended to cover the collapse rule across lenses / expanded / focus.
