# Risk report — Craft pass (Phases 0–2)

**Highest risk class: medium.**

- Path risk: touched paths are `Sources/MustardKit/Logic/` (new pure units +
  Theme additions), `Sources/MustardKit/Views/` (editor + polish), `Tests/`,
  `docs/` — matches `Sources/` → **medium** in `.agent-loop/risk.yml`.
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
