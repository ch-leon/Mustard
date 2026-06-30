## BAK-106 — Agent co-pilot dock

A persistent bottom bar (purple dot + "Agent" + derived text + "Open console →") on every screen except the Agent console — the prototype surface not named in the README.

### Changes
- `AgentInbox.pendingRecCount` / `outputCount` / `dockText(recs:outputs:)` (pure, TDD).
- RootView: co-pilot dock; "Open console →" sets `screen = .agent`.
- `AgentInboxTests` +4 dockText cases.

### Checks
swift build clean · swift test 413 pass / 1 skip / 0 failures (+4).

### Risk
Medium — shared Logic helpers + RootView; no schema/outward.
