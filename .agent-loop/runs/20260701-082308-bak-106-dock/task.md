# BAK-106 — Agent co-pilot dock (persistent bottom bar)

**Run:** 20260701-082308-bak-106-dock · **Milestone:** Redesign · Desktop delta
**Risk class:** medium (Sources/ — AgentInbox helpers + RootView)

## Done
- `AgentInbox.pendingRecCount` / `outputCount` / `dockText(recs:outputs:)` (pure, TDD) —
  "{N} recommendation(s) and {M} output(s) waiting on you" / "All clear — nothing
  waiting on you".
- RootView: a persistent bottom **co-pilot dock** (purple dot + "Agent" + derived text +
  "Open console →") shown on every screen **except** the Agent console; the link sets
  `screen = .agent`. (Mustard has no separate Settings *screen* — settings is an
  inspector — so the only exclusion is Agent.)

## Notes
This is the surface that's in the prototype but NOT the written README. `AgentInboxTests`
extended with the 4 dockText cases.
