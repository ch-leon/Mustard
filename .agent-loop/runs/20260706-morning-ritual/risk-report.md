# Risk report — Morning ritual (BAK-50)

**Highest applicable risk class: MEDIUM** → auto-merge after fresh-context review.

## Labels
- Feature work → task_label_risk **medium**.

## Touched paths
- `Sources/MustardKit/{Models,Logic,Views}/**`, docs, tests → **medium** ("Sources/")
  at most. **No high-risk paths:** no hunk touches ClaudeRunner, TrustPolicy,
  RecommendationAction, auth/oauth/token files, or workflows. The wizard's agent
  standup calls ONLY the existing `AgentService.decide`/`snooze` decision APIs — no
  new execution paths, no gating changes; trust/gating semantics untouched.

## Irreversible outward actions
- **None.** All mutations are local SwiftData task fields (`scheduledAt`,
  `focusOnDay`, `carriedForwardAt`) and two UserDefaults stamps. No claude
  invocations added anywhere in the ritual (zero subscription-cost change).

## Blast radius notes
- Ritual never run → app behaves exactly as before (carry-forward unchanged except
  a passive stamp; one dismissible banner).
- Model changes are two optional defaulted-nil fields (CloudKit-safe, ADR-0001) —
  lightweight schema addition, no migration needed.
