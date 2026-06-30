# Skill-aware, best-effort worker — design spec

- **Date:** 2026-06-29
- **Status:** Implemented (vault skill; design record only in Mustard)
- **Enhances:** Phase 3 worker (`drain-agent-queue`). Spec: `2026-06-29-agent-worker-phase3-design.md`.
- **Implementation:** `Codeheroes work/.claude/skills/drain-agent-queue/SKILL.md` (separate repo, local-only — never pushed). **No Mustard code change.**

## Why

The v1 worker hardcoded three outward actions (`draft_email`/`draft_slack`/`ticket_write`)
and declined everything else — so a real task like "kick off the prep release process"
got declined even though a skill (`dla-dlv-prep-release`) and KB knowledge exist for it.
The worker should **get any approved task done**, not classify it into a fixed menu.

## Decision

The worker is a **capable agent**, not a 3-way switch:

1. **Skill-aware routing.** Per work order, ground in the KB, then pick the best-matching
   vault skill (discovered at run time from `*/.claude/skills/*/SKILL.md` descriptions) and
   **read + follow its `SKILL.md` directly** (cross-skill `/invoke` is unreliable). Examples:
   ticket → `dl-create-shortcut-story`; release kickoff → `dla-dlv-prep-release`; email/Slack →
   the Gmail/Slack connector drafts.
2. **Best-effort when no skill fits.** Still attempt the task with reasoning + the KB +
   connectors, producing a real result. **"No skill exists" is not a reason to decline.**
3. **`actionType` is a hint, not a gate.** The bridge already exports any queued/For-Agent
   task regardless of actionType (no Mustard change needed). The worker uses actionType if
   present, else infers intent from title/body. (Supersedes BAK-89's "guard empty actionType"
   idea — the worker handles empty instead of blocking it; the *settable/carry-from-rec*
   parts of BAK-89 remain useful as hints.)

## Safety boundary (unchanged philosophy)

- **Drafts / reversible only.** Gmail/Slack *drafts*, Shortcut/Jira tickets, vault notes —
  never a final send/post or irreversible action without an explicit gating skill.
- Everything returns to **Needs Review** — draft-and-surface, never silently send.
- Verify before "done"; never fabricate scope; decline only when genuinely blocked.

## Architecture — why NOT per-task sub-agents (the question raised)

The connectors (Gmail/Shortcut/Sheets/Chrome) **and** the vault skills live in the
*connected session*. A spawned Task-tool subagent risks losing that connector + skill
access, which would defeat the purpose. So the worker stays a **single orchestrator** that
processes orders in the connected session; the vault **skills are the domain specialists**.
Per-task sub-agents are revisited only if we confirm they retain connectors + skills *and*
the queue is busy/heavy enough to want isolation/parallelism — deferred.

## Verification

It's a prompt/skill — verified by use. The earlier live run proved the skill triggers,
reads a sibling skill's `SKILL.md`, and round-trips a result. The new behaviour to confirm
when convenient: a task with no narrow actionType (e.g. "prep release") now routes to its
skill or best-efforts, instead of declining — heavy real workflows (`dla-dlv-prep-release`)
create real artifacts, so test with care.

## Follow-ups

- BAK-89 reframed: don't block empty actionType (worker handles it); keep the "settable +
  carry-from-rec" hint parts.
- The deferred scheduled routine (auto-run the worker) and the export/ingest race (BAK-92)
  are unchanged by this.
