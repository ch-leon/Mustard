# BAK-97 — Vendor design handoff + write redesign PRD

**Run:** 20260701-061603-bak-97-vendor-handoff
**Milestone:** Redesign · Desktop delta
**Risk class:** low (docs-only; no source code touched)

## Scope
Vendor the 2026 redesign handoff prototypes into the repo as the stable source of
truth and write the destination PRD, so every other redesign issue (BAK-98..119)
can reference a fixed path instead of `~/Downloads/handoff`.

## Done
- Created `docs/design/redesign-2026/` with the four product files: `Mustard.dc.html`,
  `Mustard Mobile.dc.html`, `MustardBoardCard.dc.html`, `README.md` (handoff spec).
- Deliberately excluded `support.js` and `ios-frame.jsx` (prototype runtime — never ship).
- Wrote `docs/design/redesign-2026/PRD.md`: problem, already-shipped baseline,
  desktop delta, iOS companion, implementation/testing decisions, the two parity
  discrepancies to pin (confidence thresholds; Admin dot colour), and out-of-scope.

## Out of scope
No source code changes; the parity discrepancies are documented here but fixed in
BAK-98.
