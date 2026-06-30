## BAK-117 — Parity audit: Board + card

Audited the Board + card vs the prototype (docs/design/redesign-2026/parity/board.md). Strong parity post-polish; no regressions.

### Inline fixes
- Due renders red/amber + bold when overdue (was always blue).
- Tags rendered as pill chips (bg + hairline border).
- Owner toggle is now hover-revealed (agent still shown via the left accent).
- Area chip "All areas" → "All".

### Follow-ups
- BAK-134 (header "+ New task" + Search), BAK-135 (drag-over column highlight).

### Checks
swift build clean · swift test 417 pass / 1 skip / 0 failures.

### Risk
Medium — cosmetic view edits + docs; no logic/schema/outward.
