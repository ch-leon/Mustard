## BAK-97 — Vendor design handoff + write redesign PRD

First traceable slice of the 2026 redesign. Establishes a stable in-repo source of
truth so BAK-98..119 can reference a fixed path instead of `~/Downloads/handoff`.

### Changes
- Add `docs/design/redesign-2026/` with the four product prototypes: `Mustard.dc.html`,
  `Mustard Mobile.dc.html`, `MustardBoardCard.dc.html`, `README.md` (handoff spec).
- Exclude the prototype runtime (`support.js`, `ios-frame.jsx`) — not product code.
- Add `docs/design/redesign-2026/PRD.md`: problem, already-shipped baseline, desktop
  delta, iOS companion, implementation/testing decisions, the two parity
  discrepancies to pin in BAK-98, and out-of-scope.

### Checks
- `swift build` → Build complete.
- `swift test` → 366 passed, 1 skipped, 0 failures.

### Risk
Low — docs-only; no `Sources/`, `Package.swift`, config, or outward actions.

### Notes
Documents (does not fix) two discrepancies for BAK-98: confidence-colour thresholds
and the Admin area-dot colour.
