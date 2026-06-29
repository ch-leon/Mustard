# Agent Worker (Phase 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author one on-demand orchestrator skill, `drain-agent-queue`, that reads `_agent/outbox/` work orders, performs each outward action with live connectors, writes results, and archives the orders — implementing the Phase 2 bridge contract.

**Architecture:** A single SKILL.md (a prompt, not code) in the `Codeheroes work` vault. It loops outbox work orders and dispatches by `actionType`, *invoking* the existing per-vault `*-create-shortcut-story` skills for tickets and the Gmail/Slack connectors for drafts. Per-workspace knowledge stays in those skills; the orchestrator is thin.

**Tech Stack:** Claude Code skill (Markdown + frontmatter); MCP connectors (Shortcut, Gmail, Slack, Google Sheets, Chrome); the bridge file contract (`docs/agent-bridge-contract.md`).

**Spec:** `docs/specs/2026-06-29-agent-worker-phase3-design.md`

---

## ⚠️ Where this is built (read first)

The deliverable lives in a **different repo** from Mustard:

```
/Users/leoncreed-baker/Documents/Cavehole/Codeheroes work/.claude/skills/drain-agent-queue/SKILL.md
```

- The `Codeheroes work` vault is a **separate git repo with tracked secrets in history → commit locally, NEVER push it** (memory: `codeheroes-kb-tracked-secrets`).
- Mustard's `swift test` / dev-loop / CI do **not** apply. Verification is the manual end-to-end test (Task 7).
- This plan + the spec are the design record (committed in Mustard); the skill is committed in the vault.

**Contract recap (from `docs/agent-bridge-contract.md`):**
- Read: `<KB>/_agent/outbox/<uid>.json` = `AgentWorkOrder` `{uid, mode("prep"|"execute"), actionType, title, body, area, project, sourceContext, links[], createdAt}`.
- Write: `<KB>/_agent/results/<uid>.json` = `AgentResult` `{uid, mode, status("done"|"failed"|"declined"), actionType?, title?, body?, links?:[{label,url}], summary?, error?}`.
- Archive consumed order → `<KB>/_agent/outbox/done/<uid>.json`.
- DL KB path: `/Users/leoncreed-baker/Documents/Cavehole/Codeheroes work/DL-Knowledge-Base`.

---

## File structure

One file: `.../skills/drain-agent-queue/SKILL.md`, authored in sections. It *invokes* (does not duplicate) `dl-create-shortcut-story` (`DL-Knowledge-Base/.claude/skills/`). Commits are local to the `Codeheroes work` repo.

---

## Task 1: Scaffold the skill (frontmatter + overview)

**Files:**
- Create: `Codeheroes work/.claude/skills/drain-agent-queue/SKILL.md`

- [ ] **Step 1: Write the frontmatter + overview**

```markdown
---
name: drain-agent-queue
description: Use when Leon says "drain the agent queue", "run the agent worker", "process the agent outbox", "do the queued agent tasks", or after approving tasks on the Mustard board that need executing. Reads each knowledge base's _agent/outbox work orders, performs the outward action (create a Shortcut story / Gmail draft / Slack draft) using the connectors, writes results back, and archives the orders. Implements the Mustard agent-bridge contract (Phase 3).
---

# drain-agent-queue

Execute the work orders Mustard staged on the board. Mustard (the Mac app) writes
`_agent/outbox/<uid>.json` work orders into each knowledge base; this skill performs
them in a connected session (full connectors incl. the browser for Jira) and writes
`_agent/results/<uid>.json` back, which Mustard ingests into Needs Review / Needs Approval.

**You run in a connected session** — you have Shortcut, Gmail, Slack, Google Sheets, and
Chrome. That is required: the headless agent inside Mustard cannot reach these.

## Knowledge bases (v1 = DL only)

| KB | outbox root | ticket skill |
|----|-------------|--------------|
| DL | `/Users/leoncreed-baker/Documents/Cavehole/Codeheroes work/DL-Knowledge-Base/_agent` | `dl-create-shortcut-story` |

(SB / Sandvik / Code Heroes extend later by adding their root + `*-create-shortcut-story` skill to this table — no other change.)
```

- [ ] **Step 2: Eyeball** — confirm the description's trigger phrases are natural and the KB table path matches the real DL KB folder.

- [ ] **Step 3: Commit (in the vault repo)**

```bash
cd "/Users/leoncreed-baker/Documents/Cavehole/Codeheroes work"
git add .claude/skills/drain-agent-queue/SKILL.md
git commit -m "feat(skill): scaffold drain-agent-queue (Phase 3 worker)"
```

---

## Task 2: The discover + loop section

**Files:**
- Modify: `.../drain-agent-queue/SKILL.md`

- [ ] **Step 1: Append the workflow loop**

```markdown
## Workflow

For each KB in the table above, list `<outbox root>/outbox/*.json` (IGNORE the `done/`
subfolder). If there are none, report "queue empty" and stop. Otherwise process each
work order **independently and in filename order** — one order failing must NEVER stop
the others.

For each `<uid>.json` work order:

1. **Read + parse** it as an `AgentWorkOrder`: `{ uid, mode, actionType, title, body,
   area, project, sourceContext, links, createdAt }`.
2. **Dispatch** by `mode` then `actionType` (Steps in §Execute and §Prep below).
3. **Write the result** `<outbox root>/results/<uid>.json` (§Results).
4. **Archive the order**: move `<outbox root>/outbox/<uid>.json` →
   `<outbox root>/outbox/done/<uid>.json`. Do this ONLY after the result file is written,
   so a crash mid-run leaves the order live for a retry.

Never invent fields beyond the work order. If `actionType` is `vault_note`/`create_task`
(should not appear — Mustard runs those itself), skip it: write a `declined` result with
summary "non-outward action, handled by Mustard" and archive.
```

- [ ] **Step 2: Eyeball** — confirm the loop is order-independent, archives only after writing, and skips non-outward actions safely.

- [ ] **Step 3: Commit**

```bash
cd "/Users/leoncreed-baker/Documents/Cavehole/Codeheroes work"
git add .claude/skills/drain-agent-queue/SKILL.md
git commit -m "feat(skill): outbox discover + per-order loop"
```

---

## Task 3: Execute-mode dispatch

**Files:**
- Modify: `.../drain-agent-queue/SKILL.md`

- [ ] **Step 1: Append**

```markdown
## Execute (mode == "execute")

Create the real artifact, then record its link.

### actionType == "ticket_write"
Use the KB's ticket skill (DL → the `dl-create-shortcut-story` skill). Pass the work
order's `title` as the story name and `body` as the source content. Let that skill run
its full flow (template, tasks, sub-tasks, and — if the body references a Jira key — its
Sheets lookup + Chrome reverse-link). Capture the story URL it reports
(`https://app.shortcut.com/codeheroesdw/story/<id>`).
→ result: `status:"done"`, `links:[{"label":"Shortcut","url":"<story url>"}]`, `summary` = one line.

### actionType == "draft_email"
Create a **Gmail draft** (connector `create_draft`) using the `body` as the draft content
(subject + body if the body contains them). It is a DRAFT — never send. Recipient may be
left empty for Leon to fill. Capture the draft's link.
→ result: `status:"done"`, `links:[{"label":"Gmail draft","url":"<draft link>"}]`, `summary`.

### actionType == "draft_slack"
Create a **Slack draft** via the connector (`slack_send_message_draft`) with the `body`.
Slack drafts are not reliably URL-addressable — that's expected.
→ result: `status:"done"`, `links: []` (or a link if one exists), `summary` = e.g.
"Slack draft prepared for #<channel>".

If any of these cannot be completed, write `status:"failed"` with a one-line `error`
(do NOT claim success). The task stays queued in Mustard and the next export re-issues it.
```

- [ ] **Step 2: Eyeball** — confirm ticket dispatch *invokes* `dl-create-shortcut-story` (no duplication), email/Slack are drafts only, and failures are honest.

- [ ] **Step 3: Commit**

```bash
cd "/Users/leoncreed-baker/Documents/Cavehole/Codeheroes work"
git add .claude/skills/drain-agent-queue/SKILL.md
git commit -m "feat(skill): execute dispatch (ticket/email/slack)"
```

---

## Task 4: Prep-mode dispatch

**Files:**
- Modify: `.../drain-agent-queue/SKILL.md`

- [ ] **Step 1: Append**

```markdown
## Prep (mode == "prep")

The "For Agent" path: flesh the task out for Leon's approval — do NOT create anything.

1. Read `title` + `body`. Decide the most appropriate `actionType`
   (`draft_email` / `draft_slack` / `ticket_write`).
2. Draft the content:
   - For a would-be ticket: draft the title + description using the vault template
     (`DL-Knowledge-Base/reference/Shortcut Story Templates.md` — the same template the
     `dl-create-shortcut-story` skill reads) but DO NOT file it.
   - For email/Slack: draft the message text.
3. → result: `status:"done"`, `actionType:"<chosen>"`, `title:"<refined>"`, `body:"<drafted>"`.
   Mustard moves the task to Needs Approval with this content; Leon approves → it comes
   back as an `execute` order and §Execute creates it for real.

If the task isn't actionable by the agent, return `status:"declined"` with a `summary`
(Mustard returns it to Leon). Never fabricate scope — if the source is thin, leave the
template scaffolding and say so in the summary.
```

- [ ] **Step 2: Eyeball** — confirm prep is draft-only (creates nothing), uses the same template source, and round-trips to Needs Approval → later execute.

- [ ] **Step 3: Commit**

```bash
cd "/Users/leoncreed-baker/Documents/Cavehole/Codeheroes work"
git add .claude/skills/drain-agent-queue/SKILL.md
git commit -m "feat(skill): prep dispatch (draft-only → Needs Approval)"
```

---

## Task 5: Results + hard rules

**Files:**
- Modify: `.../drain-agent-queue/SKILL.md`

- [ ] **Step 1: Append the result format + hard rules**

```markdown
## Results

Write `<outbox root>/results/<uid>.json` as exact JSON (no prose, these keys only),
mirroring the work order's `uid` and `mode`:

    { "uid": "<uid>", "mode": "<prep|execute>", "status": "<done|failed|declined>",
      "actionType": "<for prep>", "title": "<for prep>", "body": "<for prep>",
      "links": [ { "label": "...", "url": "..." } ], "summary": "<one line>", "error": "<if failed>" }

Create the `results/` directory if missing. Then archive the consumed order
(`outbox/<uid>.json` → `outbox/done/<uid>.json`).

## Hard rules — read before doing anything

1. **Never push the `Codeheroes work` repo.** It has tracked secrets. Local commits only.
2. **Verify before reporting done.** For a ticket, confirm the story exists (the ticket
   skill's own verification) before writing `status:"done"`. Never write a link you didn't
   create. Mirror `dl-create-shortcut-story`'s "STOP and re-verify" discipline.
3. **Archive only after the result is written** — order survives a crash for retry.
4. **One order's failure never blocks another.** Catch, record `failed`, move on.
5. **Drafts never send.** `draft_email`/`draft_slack` produce drafts only.
6. **Do not invent scope** (prep) — same rule as the ticket skills.

## Report

At the end, give Leon a table: per uid — KB, mode, actionType, status, and the link (or
the failure/decline reason).
```

- [ ] **Step 2: Eyeball** — result keys match the contract exactly; hard rules cover the never-push, verify-before-done, archive-after-write invariants.

- [ ] **Step 3: Commit**

```bash
cd "/Users/leoncreed-baker/Documents/Cavehole/Codeheroes work"
git add .claude/skills/drain-agent-queue/SKILL.md
git commit -m "feat(skill): result format + hard rules + report"
```

---

## Task 6: Dry structural review

**Files:**
- Read-only review of the assembled `SKILL.md`.

- [ ] **Step 1:** Re-read the whole SKILL.md top to bottom as if triggering it cold. Confirm: a reader can (a) find the outbox, (b) parse a work order, (c) dispatch every `(mode, actionType)` combination, (d) write a contract-valid result, (e) archive correctly, (f) never push the repo, (g) never claim unverified success. Fix any gap inline and amend the last commit.

- [ ] **Step 2:** Confirm the result JSON keys EXACTLY match `docs/agent-bridge-contract.md` (cross-check field names/spelling). Fix + amend if off.

---

## Task 7: Manual end-to-end test (the verification)

> Creates a REAL Shortcut story — use a throwaway and delete it after. Needs Leon's connected session + a re-authenticated `claude`.

- [ ] **Step 1:** In Mustard, approve an outward (`ticket_write`) recommendation for a DL-area task, or move a DL task to `Approved · Queued`. Confirm `DL-Knowledge-Base/_agent/outbox/<uid>.json` appears with `mode:"execute"`, `actionType:"ticket_write"`.

- [ ] **Step 2:** Trigger the skill: "drain the agent queue".

- [ ] **Step 3:** Confirm: a Shortcut story was created (open the URL); `DL-Knowledge-Base/_agent/results/<uid>.json` exists with `status:"done"` + the story link; `outbox/<uid>.json` moved to `outbox/done/`.

- [ ] **Step 4:** On the next Mustard ~10-min loop (or relaunch), confirm the task moved to `Needs Review` with the link, and the result file moved to `results/done/`.

- [ ] **Step 5:** Repeat with a `prep` (For Agent) DL task → confirm it returns to `Needs Approval` with drafted content and NO Shortcut story was created.

- [ ] **Step 6:** Delete the throwaway Shortcut test story. Record the run outcome in a short note at the bottom of the SKILL.md (or a sibling `NOTES.md`) and commit (local).

---

## Self-review

**Spec coverage:** orchestrator skill + location/caveats → Task 1 + the ⚠️ header; loop + independent processing + archive-after-write → Task 2/5; execute dispatch for all three actions, Jira via the ticket skill → Task 3; prep (draft-only → Needs Approval) → Task 4; result contract + hard rules (never-push, verify-before-done) → Task 5; DRY (invoke, not duplicate, the ticket skills) → Task 3; v1 = DL with an extension table → Task 1; manual end-to-end (incl. prep + cleanup) → Task 7.

**Placeholder scan:** none — every section's authored content is given; Task 7's steps are concrete and observable.

**Consistency:** the result JSON keys in Task 5 match the `AgentResult` contract field names used throughout; the KB table (Task 1) is referenced by the loop (Task 2) and dispatch (Task 3); `dl-create-shortcut-story` is the single ticket-creation authority (Tasks 3/4), never re-implemented.

**Note:** verification is manual by nature (a skill, in a connectors-required session that creates real artifacts) — there is no automated test gate, and that is correct for this deliverable. Mustard's side is already covered by the Phase 2 contract tests.
