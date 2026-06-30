## BAK-111 — Parity audit: Agent console

Audited the shipped Agent console + recommendation detail against the prototype (report in docs/design/redesign-2026/parity/agent-console.md). Mostly MATCH.

### Inline fixes
- ✦ glyph on Sweep button + action-type pill.
- Reasoning under a labelled WHY header (was inline).
- Gated notice → full-width banner.

### Docs
- Parity report added; PRD notes the console Review queue is board-side per ADR-0010 (README section superseded).

### Follow-ups (product decisions)
- BAK-130 dynamic header subhead; BAK-131 contextual approve labels.

### Checks
swift build clean · swift test 417 pass / 1 skip / 0 failures.

### Risk
Medium — cosmetic view edits + docs; no logic/schema/outward.
