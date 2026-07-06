# Risk report — Craft pass (Phases 0–2)

**Highest risk class: HIGH** (corrected — see below).

- The spec itself marks Phase 2 **High (NSTextView)**: a new live editing
  surface over user vault files is the product's riskiest new code regardless
  of `risk.yml` path mechanics. An earlier draft of this report classified the
  run medium from label/path matching alone — flagged by the fresh-context
  review as an unrecorded downgrade. Corrected: the run is High, and the
  `deep-review` adversarial panel was run per the high-risk merge policy
  (see `deep-review-report.md`).
- Path risk (mechanical floor, for the record): `Sources/` → medium in
  `.agent-loop/risk.yml`.
- No high-risk paths touched: no `ClaudeRunner`, no `TrustPolicy`, no
  `RecommendationAction`, no auth/oauth, no `.github/workflows/`.
- Label risk: feature work → medium.
- Outward actions: **none** — no release, no remote deletion, no secrets, no
  force push. Nothing requires Leon's explicit yes/no under `outward_actions`.
- Data-safety notes: the editor keeps the existing snapshot-before-save net
  (`FileVaultIO.snapshot`) and the text-view string == disk string invariant;
  `NoteDecoration` has no rewrite API by design; the only source-producing
  functions (`SlashMenu.insertion`, `BlockReorder.move`) are byte-pinned by
  unit tests, so vault files cannot be lossily rewritten by styling.
