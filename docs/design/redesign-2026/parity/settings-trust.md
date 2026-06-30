# Parity audit — Settings + Trust (BAK-112)

Shipped: Trust control + Sweep in the Agent console header (`AgentConsoleView.swift`);
sources in `SourceSettingsView.swift`; blurbs in `TrustPolicy.swift`. Prototype:
`Mustard.dc.html` Settings screen + README "Settings". Audited 2026-07-01.

## Structural note
The prototype has a **standalone Settings screen**; shipped Mustard folds Trust +
sources into the Agent console (per the README's "recreate using existing patterns").
Everything exists — layout differs. Filed as a follow-up decision, not a gap.

## Fixed inline (this issue)
- **Trust blurbs aligned to the prototype copy, verbatim** (`TrustPolicy.swift`) — the
  shipped strings were truncated paraphrases that dropped the gated-channel reassurances.
- **Always-visible trust blurb** under the control (was only in menu items / tooltip).
- **Gated footer note** added: "🔒 Email, Slack and tickets are always reviewed by you —
  at every trust level." (was absent).

## MATCH
- Four trust levels (Manual/Supervised/Trusted/Autonomous); "✦ Sweep" (exact);
  source cards with last-swept text; "+ Connect a source" affordance (reworded).

## Intentional / out of scope
- "(future) configurable gated-action rules" — not in the prototype; YAGNI, not a gap.

## Follow-ups filed (larger UI)
- Trust **segmented control** (active-purple) replacing the dropdown `Menu`.
- Standalone **Settings screen** + per-source "● Connected" state on every source row
  (shipped shows Connected only for Google Calendar; projects use an enable toggle).

## Minor, left as-is
- Section label "PROJECTS" vs "SOURCES"; "Add project…" vs "Connect a source" — Mustard's
  data model is project-based; equivalent.
