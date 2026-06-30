# Parity audit — Board + card (BAK-117)

Shipped `BoardView.swift` + `MustardBoardCard.swift` + `PersonalBoard.swift` +
`TaskStage.swift` vs the prototype (`Mustard.dc.html` Board, `MustardBoardCard.dc.html`,
README Board). Audited 2026-07-01 (post BAK-99/100/101/102 polish).

## Result: strong parity. No regressions from the recent polish.

### MATCH
Header title + "N waiting on you" review-focus toggle; owner segmented control (Agent
active = purple) + correct per-owner column sets; area chips AND owner; per-view caption;
column width/accent/label/count/sub-label + kinds; horizontal scroll; auto-collapse
empties (Everyone); per-column "+ Add"; "Drop here"; drag-to-restage + ownership
reassignment. Card: priority flag, ✦ Proposed pill, 🔒, title, area+source meta,
confidence row, status pill, blocked reason, hover inline gate actions, left accent.

### Fixed inline (this issue)
- **Due renders red/amber + bold when overdue** (was always blue) — `Theme.Palette.warning`.
- **Tags rendered as pill chips** (bg + hairline border) instead of plain text.
- **Owner toggle is now hover-revealed** (was persistent) — matches the handoff; agent
  ownership is still always visible via the left accent border.
- Area chip "All areas" → **"All"**.

### Follow-ups filed (larger)
- **BAK-134** — header "+ New task" + Search affordances (need a create-sheet entry + a
  title filter; not just per-column quick-add).
- **BAK-135** — drag-over column highlight (`isTargeted` visual feedback).
