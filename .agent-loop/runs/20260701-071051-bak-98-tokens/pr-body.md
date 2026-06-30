## BAK-98 — Design-token consolidation + confidence threshold + Admin dot

Makes `Theme` the canonical home for the 2026 handoff token set, removes the
confidence-colour threshold drift, and aligns the Admin area-dot to the handoff.

### Changes
- **Theme.swift**: handoff token set (surfaces, agent tints, done/review, warn,
  muted-status, confidence, priority, area dots); `ConfidenceTier` +
  `confidenceTier(_:)` + `confidenceColor(_:)` (single source: ≥0.7/≥0.5);
  centralised `sourceBadge(for:)`.
- **Drift fix**: `RecommendationDetailView` + `AgentConsoleView` used a ≥0.4 amber
  cutoff; both now call `Theme.confidenceColor` (≥0.5). 0.40–0.49 confidence now
  renders red (low), matching the board card + mobile + README.
- **MustardBoardCard / BoardView.ColumnStyle**: inline handoff hex → `Theme` tokens
  (values preserved; renders identically). Card source-badge map → `Theme.sourceBadge`.
- **PreviewData**: Admin dot is now green `#3E8E7E` (own Area); per-list-vs-by-Area
  colour gap documented.
- **Tests**: `ThemeTests` (TDD) lock the tier thresholds.
- **Docs**: PRD discrepancies marked resolved.

### Checks
- `swift build` → Build complete.
- `swift test` → 377 passed, 1 skipped, 0 failures (+3 ThemeTests).

### Risk
Medium — `Sources/` token refactor; no auth/trust/ClaudeRunner. Only behaviour change
is the intended confidence-colour drift fix.

### Follow-up (deferred, not blocking)
Exact handoff per-list dot colours under a shared group header need a per-list
`colorHex` (model change). Captured in `docs/design/redesign-2026/PRD.md`.
