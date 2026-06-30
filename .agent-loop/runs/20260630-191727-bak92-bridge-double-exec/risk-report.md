# Risk Report — BAK-92

Declared task risk: none from label (`Bug` is not in any `task_label_risk` list)
Touched-path risk: **medium** (`Sources/` matches medium; no high path matched —
  not ClaudeRunner / TrustPolicy / RecommendationAction / auth / oauth / secret)
Highest risk: **high** (escalated — see Decision)
Needs deep-review panel: **yes**
Irreversible outward actions: **none**

## Evidence
Task labels: `Bug`
Changed files:
- Sources/MustardKit/Agent/AgentService.swift   → Sources/ (medium)
- Sources/MustardKit/Agent/BridgeIO.swift        → Sources/ (medium)
- Sources/MustardKit/Logic/BridgeExport.swift    → Sources/ (medium)
- Tests/MustardTests/AgentBridgeServiceTests.swift → Tests/ (low)
- Tests/MustardTests/BridgeExportTests.swift       → Tests/ (low)

Policy matches:
- `path_risk.medium: ["Sources/"]` — all three source files.
- `path_risk.high` — no match (none of the listed high paths touched).
- `outward_actions` — none performed by this change. The fix is pure logic + a
  non-mutating directory listing (`liveResultUIDs`). It performs no deploy / send /
  delete / secret-rotation / force-push.

## Decision
**HIGH → robot deep-review panel before merge.**

By the literal `risk.yml` table this lands at **medium** (Sources/ paths, no high
path match, label not high). I am escalating to **high** because:
1. The change alters the **agent work-dispatch correctness path** — `BridgeExport.plan`
   is the gate that decides whether an *outward-action* order (email/Slack/ticket) is
   (re-)issued. The bug's blast radius was duplicate real-world actions.
2. Precedent: prior AgentService changes (BAK-83, BAK-87) were classified high in the
   digest.
3. `risk.yml` states over-matching high is cheap (robot panel only, never a human
   gate) and under-matching is the risk to avoid — so when genuinely uncertain on the
   agent loop, escalate.

The change itself performs no irreversible outward action, so there is **no human
gate** — merge-policy routes to the adversarial `deep-review` panel and auto-merges
if it passes.
