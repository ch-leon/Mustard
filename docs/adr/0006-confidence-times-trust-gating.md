# ADR-0006 — Auto-run gated by confidence × trust, with always-gated actions

**Status:** Accepted (2026-06-13)

## Context
The predecessor's triage cards carried a **confidence** score; Mustard added a
per-agent **trust** ladder. Either alone is blunt: trust without confidence
auto-runs shaky proposals; confidence without trust never graduates. The spec also
fixes a set of outward actions that must never auto-run.

## Decision
An agent recommendation **auto-runs only when** it is not a gated action AND
`trust ≥ supervised` AND `confidence ≥ autoConfidenceThreshold` (0.7). It
**auto-accepts** its output only when additionally `trust ≥ trusted`.

- Trust ladder: Manual → Supervised → Trusted → Autonomous.
- **Always-gated** (regardless of trust/confidence): `draft_email`, `draft_slack`,
  `ticket_write` (`RecommendationAction.isGated`). Vault writes may graduate.
- Logic is pure in `TrustPolicy`; both knobs
  (`autoConfidenceThreshold`, `isGated`) are one-line tunable after real use.

## Consequences
- Low-confidence work always surfaces for review even when Autonomous.
- Outbound side-effects (email/Slack/tickets) are never silent.
- Thresholds expected to be tuned once Leon has driven real sweeps.
