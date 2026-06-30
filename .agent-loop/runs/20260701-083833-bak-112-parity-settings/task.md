# BAK-112 — Parity audit: Settings + Trust control

**Run:** 20260701-083833-bak-112-parity-settings · **Milestone:** Redesign · Desktop delta
**Risk class:** HIGH (touches TrustPolicy.swift — a high-risk path per risk.yml). The
edit is display-copy only (the `blurb` strings), no gating logic, but path policy
routes it to the deep-review panel (robot, no human gate).

## Done
- Audited Settings/Trust vs prototype (report: docs/design/redesign-2026/parity/settings-trust.md).
- **Trust blurbs aligned to the prototype copy, verbatim** (`TrustPolicy.blurb`) — were truncated paraphrases.
- **Always-visible trust blurb** + **gated footer note** ("🔒 Email, Slack and tickets are always reviewed by you — at every trust level.") added under the Trust control (`AgentConsoleView.sourceRow`).
- Follow-ups filed: BAK-132 (Trust segmented control), BAK-133 (standalone Settings screen + per-source Connected).

## Out of scope
"(future) configurable gated-action rules" — YAGNI (not in prototype). Section label
"PROJECTS"/"Add project…" left (project-based model).
