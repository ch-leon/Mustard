# Risk Report — BAK-84

Declared task risk: low–medium (label `Improvement`, not in any risk list → falls to path)
Touched-path risk: medium (`Sources/` — BridgeProtocol + BridgeIO + AgentService)
Highest risk: **medium**
Needs deep-review panel: **no**
Irreversible outward actions: **none**

## Evidence
Task labels: `Improvement`
Changed files:
- Sources/MustardKit/Logic/BridgeProtocol.swift  → Sources/ (medium)
- Sources/MustardKit/Agent/BridgeIO.swift          → Sources/ (medium)
- Sources/MustardKit/Agent/AgentService.swift      → Sources/ (medium) · ingestAgentResults only
- Tests/MustardTests/FileBridgeIOTests.swift, AgentBridgeServiceTests.swift → Tests/ (low)

Policy matches:
- `task_label_risk` — `Improvement` matches none; no escalation from label.
- `path_risk.high` — no match.
- `outward_actions` — none. Quarantine MOVES a local file aside within the vault's
  `_agent/` tree; no send/deploy/delete-remote/secret/force-push.

## Decision
**MEDIUM → auto-merge after fresh-context review.** No panel.

The AgentService touch is one additive hygiene call in `ingestAgentResults` (+ a
doc-comment refresh) — no dispatch/gating/execution control flow — so not escalated to
high (consistent with BAK-91). Quarantine only relocates files Mustard already ignores.
