# Risk Report — BAK-91

Declared task risk: medium (label `Feature`)
Touched-path risk: medium (`Sources/` — new Logic helper + AgentService + a View)
Highest risk: **medium**
Needs deep-review panel: **no**
Irreversible outward actions: **none**

## Evidence
Task labels: `Feature`
Changed files:
- Sources/MustardKit/Logic/TaskLinkExtractor.swift  → Sources/ (medium) · new pure helper
- Sources/MustardKit/Agent/AgentService.swift       → Sources/ (medium) · materializeTask only
- Sources/MustardKit/Views/TaskDetailSheet.swift     → Sources/ (medium)
- Tests/MustardTests/TaskLinkExtractorTests.swift, AgentTests.swift → Tests/ (low)

Policy matches:
- `task_label_risk.medium: ["feature"]`.
- `path_risk.high` — no match.
- `outward_actions` — none. The change reads/parses text and stamps fields on a newly
  created inbox task; performs no send/deploy/delete/secret/force-push.

## Decision
**MEDIUM → auto-merge after fresh-context review.** No panel.

Note on the AgentService touch: unlike BAK-92 (export dispatch correctness) and BAK-90
(`delegate` hand-off control), this change is confined to `materializeTask` and is
purely additive provenance-stamping (sets `task.sourceURL` + `task.links` from a pure
extractor). It contains no dispatch/gating/execution control flow — worst-case blast
radius is a wrong/missing link on an inbox task (cosmetic). So **not** escalated to high.
