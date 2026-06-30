## BAK-102 — Board column polish

Empty columns auto-collapse to thin tap-to-expand strips in the Everyone lens (not in Mine/Agent or review-focus), and empty columns now read "Drop here". Per-column "+ Add" already existed (QuickColumnAdd).

### Changes
- `PersonalBoard.shouldCollapseEmpty(view:isEmpty:expanded:reviewFocus:)` (pure, TDD).
- `BoardView`: `collapsedStrip` + `isColumnEmpty` + `expandedEmpty` state; placeholder "—" → "Drop here".
- `BoardFocusTests` extended (collapse rule across lenses/expanded/focus).

### Checks
swift build clean · swift test 393 pass / 1 skip / 0 failures (+5).

### Risk
Medium — view + Logic helper; no schema/outward.
