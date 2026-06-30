# BAK-98 — Design-token consolidation + confidence threshold + Admin dot

**Run:** 20260701-071051-bak-98-tokens
**Milestone:** Redesign · Desktop delta
**Risk class:** medium (touches `Sources/` — Theme + 4 views/seed; no auth/trust/ClaudeRunner)

## Scope
Make `Theme` the canonical home for the handoff token set; kill the confidence
threshold drift; align the Admin area-dot to the handoff intent. No visual change to
already-correct surfaces (every migrated hex preserved exactly).

## Done
- **Theme.swift**: added the handoff token set — surfaces (titleBar/sidebar/chipActive/
  navActive/divider), text (onSurface/onSurfaceSoft/textMuted/strikethrough), agent
  tints, done/review, warn, muted-status, confidence (high/medium/low/unfilled),
  priority, area dots. Added `ConfidenceTier` + `confidenceTier(_:)` + `confidenceColor(_:)`
  (single source of truth: ≥0.7 / ≥0.5) and a centralised `sourceBadge(for:)` map
  (Gmail/Xero/Notes/Slack/Linear/KB).
- **Drift fix**: `RecommendationDetailView` and `AgentConsoleView` were colouring
  confidence with a ≥0.4 amber cutoff; both now call `Theme.confidenceColor` (≥0.5).
  `MustardBoardCard` already used ≥0.5 — now also routes through the helper.
- **MustardBoardCard**: every inline handoff hex → `Theme` token; local source-badge
  map removed in favour of `Theme.sourceBadge`. Only `Color(hex: area.colorHex)`
  remains (dynamic user data — correct).
- **BoardView.ColumnStyle**: per-kind hexes → `Theme` tokens (opacities unchanged).
- **PreviewData**: each handoff "area" now its own Area carrying the canonical dot
  hex — DLA SDK blue / **Admin green #3E8E7E** / Errands purple / Reading grey.

## TDD
`ThemeTests.test_confidenceTier_*` written first (failed — no helper), then Theme
implemented. Locks ≥0.7 high / ≥0.5 medium / else low, incl. 0.40 → low (the drift).

## Documented gap (per "seed fix + document" decision)
Mustard colours dots **by Area**; the handoff colours **per list**. Exact per-list
colour under a shared group header (e.g. Errands purple vs Reading grey under one
"Personal") needs a per-list `colorHex` — a model change, deferred. Captured in
`docs/design/redesign-2026/PRD.md`.

## Out of scope
No model change; group-header (Code Heroes/Personal) sidebar grouping not modelled.
