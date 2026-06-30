## BAK-112 — Parity audit: Settings + Trust

Audited Settings/Trust vs the prototype (docs/design/redesign-2026/parity/settings-trust.md).

### Fixes
- Trust **blurbs aligned to the prototype copy, verbatim** (`TrustPolicy.blurb` — display strings only; no gating logic touched).
- **Always-visible trust blurb** + **gated footer note** ("🔒 Email, Slack and tickets are always reviewed by you — at every trust level.") under the Trust control.

### Follow-ups
- BAK-132 (Trust segmented control), BAK-133 (standalone Settings screen + per-source Connected).

### Risk
HIGH by path policy (touches TrustPolicy.swift) — copy-only change, no gating logic; deep-review panel run.

### Checks
swift build clean · swift test 417 pass / 1 skip / 0 failures.
