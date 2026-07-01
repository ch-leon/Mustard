# Agent worker (Phase 3) — design spec

- **Date:** 2026-06-29
- **Status:** ✅ Implemented + live-tested (2026-06-29/30). This doc is the design record; the worker itself is a **vault skill**, not Mustard code — `Codeheroes work/.claude/skills/drain-agent-queue/SKILL.md` (separate repo, local-only, never pushed). A live run drained an order → created a full Shortcut Spike → wrote a contract-valid result → archived. Superseded/enhanced by [`2026-06-29-skill-aware-worker-design.md`](2026-06-29-skill-aware-worker-design.md) (the worker became skill-aware + best-effort, no longer a fixed 3-action switch). **Still deferred:** a scheduled routine wrapping the skill (unattended; Jira browser step needs a logged-in session) and extending the KB table beyond DL (SB/Sandvik/Code Heroes).
- **Phase:** 3 of 3 of the Agent Task Board. Phase 1 (board + `stage`) and Phase 2 (the vault-file bridge) are merged (PRs #26, #27; ADR-0010).
- **Implements:** the Phase 2 file contract — `docs/agent-bridge-contract.md` (`_agent/outbox/*.json` work orders → `_agent/results/*.json`).

## Why

Phase 2 makes Mustard *write* work orders and *ingest* results, but nothing yet reads the outbox and does the work. Phase 3 is the **worker**: a connected Claude session that drains `_agent/outbox/`, performs each outward action with the live connectors (Shortcut/Gmail/Slack, plus Sheets + browser for Jira), and writes results back. This is the piece that finally turns an approved `queued` task into a real Shortcut story / Gmail draft / Slack draft, returned as a reviewable link.

It is **connector-bound by necessity** — the headless `claude -p` Mustard runs has no connectors (ADR-0003), and the DL Shortcut flow needs Google Sheets + a logged-in browser for the Jira reverse-link. So the worker runs in a **connected session** where those exist.

## Where it lives (important — different from Phases 1–2)

The worker is **not Mustard Swift code.** It is a single orchestrator **skill** authored in the **`Codeheroes work` vault**:

```
Codeheroes work/.claude/skills/drain-agent-queue/SKILL.md
```

That vault level can see every sub-vault's `_agent/`, the vault `.mcp.json` (per-workspace Shortcut tokens via `SHORTCUT_DL_TOKEN` etc.), and the existing per-vault `*-create-shortcut-story` skills.

**Repo caveats (load-bearing):** the `Codeheroes work` vault is a *separate* git repo with **tracked secrets in history** — commits stay **local only; never push it**. Mustard's dev-loop (`swift test`, risk policy, this repo's CI) does **not** govern this skill. This Mustard spec is the design record; the skill is built and committed in that vault.

## Scope (v1)

- **One orchestrator skill**, `drain-agent-queue`, run **on-demand** in a connected session. (A scheduled local routine that invokes the same skill is a later wrap — out of scope.)
- Handles **both modes** the bridge emits: `execute` (queued) and `prep` (forAgent).
- Handles **all three outward action types**: `ticket_write`, `draft_email`, `draft_slack`.
- **v1 proves the DL knowledge base end-to-end.** Other vaults (SB/Sandvik/Code Heroes) light up by dispatching to their own `*-create-shortcut-story` skills once those are confirmed — no worker change needed.
- **DRY:** the worker is thin orchestration; per-workspace ticket knowledge stays in the existing `*-create-shortcut-story` skills, which it *invokes* rather than re-implements.

**Out of scope:** the scheduled routine; non-outward actions (`vault_note`/`create_task` — Mustard runs those headless, they never reach the outbox); any change to Mustard Swift code.

## The loop

For each target KB (v1: DL), list `_agent/outbox/*.json` (skip the `done/` subfolder). Process each work order **independently** — one failure never blocks the rest. Steps per order:

1. Read + decode the `AgentWorkOrder` (uid, mode, actionType, title, body, area, project, links).
2. Dispatch (below).
3. Write `_agent/results/<uid>.json` per the contract.
4. Move the consumed order to `_agent/outbox/done/<uid>.json`.

### Dispatch — `execute` mode

| actionType | action | result `status: done` carries |
|---|---|---|
| `ticket_write` | invoke the vault's `*-create-shortcut-story` skill (DL → `dl-create-shortcut-story`) with the order's title/body; that skill does the full flow incl. tasks/sub-tasks and, for Jira-linked, the Sheets lookup + Chrome reverse-link | `links: [{label:"Shortcut", url: app.shortcut.com/…}]`, `summary` |
| `draft_email` | create a **Gmail draft** via the connector from the body (recipient left for Leon — it's a draft, never sent) | `links: [{label:"Gmail draft", url}]`, `summary` |
| `draft_slack` | create a **Slack draft** via the connector | `summary` describing it; `links` may be empty (Slack drafts aren't reliably URL-addressable — accepted for v1) |

### Dispatch — `prep` mode

The For-Agent path: the task needs fleshing out before approval. The worker reads the title/body, **determines the actionType and drafts the content** (for a would-be ticket, draft the title+description using the vault template the `*-create-shortcut-story` skill references — *without filing it*), and returns a `prep`/`done` result with `actionType` + `body`. Mustard moves the task to `needsApproval`. It does **not** create any artifact in prep mode. If the agent judges the task isn't actionable, it returns `status: declined` with a `summary` (Mustard returns it to you).

### Failures / declines

Any step that can't complete → `status: failed` with `error` (Mustard surfaces it; the task stays at its source stage, so the next Mustard export re-issues the order → natural retry) or `status: declined` with `summary` (task returns to you). The worker never claims success it didn't achieve (mirrors `dl-create-shortcut-story`'s "verify before reporting done" rule).

## Idempotency

A work order present in `outbox/` (not `done/`) is unprocessed; once the worker writes its result and archives the order, a re-run won't re-read it. Mustard's ingest stage-guard is the backstop on the other side. The worker must archive the order **only after** the result file is written (so a crash mid-run leaves the order live for retry, never silently lost).

## Connectors / prerequisites

Shortcut MCP (per-vault tokens, already in the vault `.mcp.json`); Gmail connector (`create_draft`); Slack connector (draft/scheduled-message); Google Sheets + Chrome (for Jira-linked, used by `dl-create-shortcut-story`); a re-authenticated `claude` CLI. All present in Leon's connected session.

## Verification

No unit tests (it's a skill). Manual end-to-end, recorded in the skill's notes:
1. In Mustard, approve an outward recommendation → task at `Approved · Queued` → confirm `<DL KB>/_agent/outbox/<uid>.json` appears (`mode:"execute"`).
2. Run `drain-agent-queue` in a connected session.
3. Confirm: the Shortcut story (or Gmail/Slack draft) is created; `_agent/results/<uid>.json` is written with the link; the order is in `outbox/done/`.
4. On the next Mustard loop, confirm the task moves to `Needs Review` with the link, and the result is archived to `results/done/`.
5. Repeat for a `prep` (For Agent) task → confirm it returns to `Needs Approval` with drafted content, no artifact created.

## Open risks

- **Slack drafts** have no reliable shareable URL; the result documents the draft rather than linking it. Accepted for v1; revisit if a better Slack target emerges.
- **Unattended capability:** a future scheduled routine wrapping this skill may not have the logged-in browser, so Jira-linked stories could fail there — to be addressed when/if the routine is built (the on-demand skill in a connected session is the v1 promise).
- **Re-auth dependency:** the `claude` CLI token expired once already (ADR-0003 note); if the worker session 401s, re-auth via `claude setup-token`.
