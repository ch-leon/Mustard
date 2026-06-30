# Risk Report — BAK-89

Declared task risk: medium (label `Feature` → `task_label_risk.medium`)
Touched-path risk: medium (`Sources/` — BridgeExport + two Views; no high path matched)
Highest risk: **medium**
Needs deep-review panel: **no**
Irreversible outward actions: **none**

## Evidence
Task labels: `Feature`
Changed files:
- Sources/MustardKit/Logic/BridgeExport.swift   → Sources/ (medium)
- Sources/MustardKit/Views/TaskDetailSheet.swift → Sources/ (medium)
- Sources/MustardKit/Views/MustardBoardCard.swift → Sources/ (medium)
- Tests/MustardTests/BridgeExportTests.swift      → Tests/ (low)

Policy matches:
- `task_label_risk.medium: ["feature"]` — matches.
- `path_risk.high` — no match (BridgeExport/Views are not ClaudeRunner/TrustPolicy/
  RecommendationAction/auth/oauth/secret; no AgentService change this time).
- `outward_actions` — none. The change makes export STRICTER (skips an unroutable
  order) and adds UI; it performs no send/deploy/delete/secret/force-push.

## Decision
**MEDIUM → auto-merge after the fresh-context review passes.** No deep-review panel,
no human gate. (Contrast BAK-92, which touched AgentService and was escalated to high.)
