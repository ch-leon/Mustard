# ADR-0010 — Decoupled agent execution via the board queue

**Status:** Accepted (2026-06-29). **Supersedes the execute→OutputCard half of ADR-0006.**

## Context
We wanted "Approve a recommendation → the agent actually creates the artifact" (a
Shortcut ticket, an email draft). Two hard constraints make Mustard creating it inline
impossible:
- The headless `claude -p` runs with a scrubbed env and no connectors (ADR-0003), so it
  cannot reach Gmail/Slack/Shortcut.
- The canonical DL Shortcut skill (`dl-create-shortcut-story`) needs the Google Sheets
  connector and a logged-in browser (Jira reverse-link) — neither available headless.

So the artifact-creating work has to run in a **connected** Claude session, which is not
a background, always-on facility. Forcing Mustard to drive it inline (live progress, an
`OutputCard` review gate) modelled an execution Mustard cannot actually perform.

## Decision
Agent work is **staged on the board, executed out of band.**
- `MustardTask` gains a single `stage` (10-stage pipeline) as its source of truth,
  replacing `TaskStatus` and the previously-derived `DelegationPhase`. One task, one
  stage, one owner.
- Approving a recommendation **promotes** it to a `queued` task (in-vault actions —
  vault note / create task — can still run headless straight to `done`). You can also
  delegate manually: `forAgent` → (prep session) → `needsApproval` → approve → `queued`.
- A **decoupled session/routine** (a skill you run, or a local routine) pulls from
  `queued`, performs the action with full connectors, and writes results back into
  `needsReview` carrying **links** (Shortcut/Jira/draft). No live progress; no inline
  `running` state.
- `OutputCard` is **retired** — its review role becomes the `needsReview` stage + links.
- Mustard and the session communicate through **vault files** (the board has no API a
  skill can query), reusing the `_recs/` → `InboxIngest` pattern (ADR-0008), both
  directions. That bridge + the worker are later phases.

## Consequences
- Gating is preserved: outward/connector actions still require Approve; trust still
  governs auto-run of non-gated work (ADR-0006's gating half stands). Only the
  execute→review-card mechanism is replaced.
- Agent artifact creation is **not fully autonomous/background** — it needs the connected
  session to run. Accepted, in exchange for full skill fidelity (Jira included).
- Today/Week/Hover/Notch and the console move from `status`/`DelegationPhase` reads to
  `stage`; `someday` is dropped (accepted data loss).
- **Deferred:** the file bridge (Phase 2) and the worker skill/routine (Phase 3), each
  with its own spec. Design: `docs/specs/2026-06-29-agent-task-board-design.md`.
