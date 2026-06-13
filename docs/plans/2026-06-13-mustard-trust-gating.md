# Mustard — Trust & Gating (Plan 4 of N)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** Spec §8d. A trust level that decides how much the agent does without you, plus a fixed set of always-gated action types that never auto-run regardless of trust.

**Model:**
- `TrustLevel`: `manual | supervised | trusted | autonomous` (ordered).
- `GatedActionType` set: `email_send`, `ticket_write`, `slack_post` (vault_note is NOT gated).
- `TrustPolicy` (pure, tested):
  - `isGated(actionType:)` — membership in the always-gated set.
  - `shouldAutoApprove(actionType:trust:)` — true iff trust ≥ supervised AND not gated.
  - `shouldAutoAccept(actionType:trust:)` — true iff trust ≥ trusted AND not gated.
  - So: manual = you approve everything; supervised = auto-runs non-gated, you review output; trusted/autonomous = auto-runs and auto-accepts non-gated output. Gated actions always wait, every level.

**Wiring:**
- `AgentService.execute` returns the `OutputCard` so auto-accept can act on it.
- `AgentService.applyTrust(_:)` iterates pending recommendations: auto-approve+execute eligible ones serially, auto-accept their cards when the level allows.
- `sweep` calls `applyTrust(storedTrust())` after inserting; `storedTrust()` reads `@AppStorage("trustLevel")`.
- Console: a Trust menu (4 levels) + a lock badge on recommendations whose action type is gated; raising trust re-runs `applyTrust` on the backlog.

**Tasks:** (1) `TrustPolicy` + tests, commit. (2) `execute` returns card + `applyTrust` + sweep hook + AgentService tests, commit. (3) Console trust menu + gated badge, build/relaunch, commit.

**Done when:** tests green; setting Trusted and sweeping a vault auto-runs and auto-accepts vault recommendations while a (synthetic) email_send recommendation stays pending.
