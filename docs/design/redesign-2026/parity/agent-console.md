# Parity audit — Agent console (BAK-111)

Shipped `AgentConsoleView.swift` + `RecommendationDetailView.swift` vs the prototype
(`Mustard.dc.html` Agent screen + README "Agent console"). Audited 2026-07-01.

## Result: parity good. Most elements MATCH.

### MATCH
- Recommendation rows: source badge, context, ✦ + title, 🔒 gated, confidence (numeric +
  5 bars), selected-row treatment, empty-state copy ("Nothing waiting on you. Run a sweep.").
- Sweep behaviour (label → "Sweeping…", disabled while running).
- RE-BUCKET: all 7 chips (Draft email / Draft Slack / Create task / Update vault /
  Shortcut ticket / FYI / Ignore).
- PROPOSED DRAFT (shipped is editable — an enhancement over the read-only prototype).
- Action buttons: Comment, Snooze ▾, Schedule, I'll do it, Reject. (Shipped adds an
  FYI Keep/Dismiss branch — enhancement.)

### Fixed inline (this issue)
- ✦ glyph added to the Sweep button label and the action-type pill.
- Reasoning now rendered under a labelled **WHY** section header (was inline "Why ·").
- Gated notice promoted to a full-width banner ("{action} — always reviewed by you,
  regardless of trust level.") instead of a compact inline label.

### Intentional divergences (NOT gaps)
- **Review queue:** the prototype + README:105 still show a console-resident REVIEW
  queue, but the shipped app intentionally moved review to the **board's Needs Review
  column (ADR-0010)**. The console correctly omits it. README:105 is stale relative to
  ADR-0010 — see the note added to PRD.md so future audits don't re-flag this.

### Minor, deliberately left as-is
- Snooze option wording ("1 hour / This evening / Tomorrow" vs prototype "Later today /
  Tomorrow / Next week") — equivalent; not worth churn.
- Feedback input shown via the Comment toggle rather than always-visible — equivalent.

### Follow-ups filed (larger product decisions, not silent edits)
- Header subhead (dynamic "plans your day with you" / "reviewing your sources…") is
  absent; shipped uses an inline progress + "Auto-open source" toggle instead.
- Contextual approve labels ("Approve & run" / "Approve & schedule") vs shipped generic
  "Approve" + separate "Schedule".
