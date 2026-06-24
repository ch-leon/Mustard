# Source Cadence + Channel Routing — Design

**Date:** 2026-06-22
**Status:** Approved (brainstormed with Leon 2026-06-22; cadence amended 2026-06-24 — see A.1)
**Related:** ADR-0008 (local-only email scout — this *switches it on*), `docs/scout-routine-prompt.md`, F17 (meeting ingest), F18 (source-ingestion foundation).

## Problem

Leon wants **email / Jira / Shortcut** and **meeting tasks** flowing in frequently, and the **vault sweep** only occasionally. The current setup is inverted:

- `meetingVaultPath` is **unset** → the meeting-task harvest is gated off → no meeting tasks flow.
- The `inbox-sweep` scout (`~/.claude/scheduled-tasks/inbox-sweep`) is **"Manual only"** → no email/Jira/Shortcut recs since its one manual run on 2026-06-18.
- The vault sweep source migrated with **interval 0 = off** (`SweepScheduler.isDue` returns false for `intervalHours == 0`), so it only runs on a manual ⌘K. (The VAULT card pile seen in testing came from *manual* sweeps, not auto-flooding.) This already matches "rare/manual" — no change needed.

Separately, testing surfaced three recommendation-quality gaps (seen on VAULT cards): wrong channel (a Slack draft for a non-Slack external party), prose-wall drafts for multi-item actions, and confident "create a ticket" recs for items blocked on an external party.

## Decisions

### A. Cadence — config only, no code

1. **`inbox-sweep` → twice daily, 6:30am & 1pm, weekdays** (cron `30 6,13 * * 1-5`). *(Amended 2026-06-24 — originally hourly `0 6-17 * * 1-5`; cut back to the scout prompt's intended ~2×/day.)* Give the existing routine a cron (it was Manual only). It's idempotent (identity = Gmail message id; already-seen ids are skipped) and runs locally. Because the gap between runs is now large (up to ~66h across a weekend: Fri 1pm → Mon 6:30am), the scout prompt scopes each run to `newer_than:3d` and reviews **all** of it — a window deliberately wider than the largest gap — so an email arriving since the last run can't be buried under newer mail and missed; the message-id dedup makes the overlapping re-scan free of duplicates. New email/Jira/Shortcut recs reach the app at the next run (≤~7h during the day; overnight/weekend longer) + the existing ~10-min `_recs/` ingest loop. Jira/Shortcut remain **notification-led** (scope A) — direct API sweeps deferred.
2. **Meeting tasks → set `meetingVaultPath` = `…/Codeheroes work`** (the parent of the sub-vaults; harvests DL + SB + Sandvik + CH `meetings/`). Mustard reconciles meeting-note tasks **every 60s in-app** once set (a free local file-parse, no model call) — far more frequent than the inbox sweep; no throttle added. One small code fix: `FileVaultIO.meetingNotePaths()` must **prune `node_modules`/`.git`** when enumerating — `Codeheroes work` is ~32k files, ~92% under `sites/**/node_modules`, so the 60s walk would otherwise visit ~30k irrelevant files each tick. Results are unchanged (the `meetings/` filter already excludes them) — pure perf prune.
3. **Vault sweep → already off; no change.** The DL vault source migrated with `intervalHours == 0`, which `SweepScheduler` treats as off — so auto-sweep is already disabled and it only runs on a manual ⌘K. Leave it. (The Source Settings panel offers Off / Hourly / 4h / Daily if a schedule is ever wanted.)

### B. Channel routing rule — applies to both prompts

When proposing an outbound action: **internal team → Slack; external partners (TMR / CDSB / Thales / etc.) → email; channel unknown → a task for Leon to chase.** Consult the project's `people/` / `partners/` notes for the channel; never default to Slack for an external party.

### C. `VaultSweep.prompt` quality fixes — the only Mustard code change

1. **Channel rule** (B) folded into the recommendation prompt's action-type/draft guidance.
2. **Multi-item drafts → enumerate.** When one action covers several items (e.g. "raise stories for these defects"), the draft must be a scannable list — one line per item with its id + summary — not a prose paragraph.
3. **Externally-blocked items → demote.** If a notes item is blocked / awaiting an external party, propose `fyi` ("still waiting on X — no action") or skip it; do not raise a confident ticket.

### D. Scout `SKILL.md` prompt

Add the channel rule (B) to `inbox-sweep`'s draft guidance (same rule, so its `draft_email` vs `draft_slack` choices come out right). *(Amended 2026-06-24: also added the `newer_than:3d` "SCOPE THE SCAN" lookback — see A.1 — so the twice-daily cadence can't miss buried mail. Synced to `docs/scout-routine-prompt.md`.)*

## Out of scope (YAGNI / deferred)

- **Direct Jira/Shortcut API sweep sources** (scope B) — deferred; revisit only if notification-led intake proves to miss things.
- **Cloud routine / git sync** — ADR-0008 stands: local-only.
- **Mac-independence / mobile** — deferred.
- Multi-item draft *structure* changes to the scout (it's mostly 1-email→1-rec); the enumerate rule (C2) is for the vault sweep where multi-item actions arise.

## Mechanics — who changes what

| Change | Where | In the Mustard repo? |
|---|---|---|
| `inbox-sweep` cron (twice daily, weekdays) | `~/.claude/scheduled-tasks/inbox-sweep` | no — Leon's Claude routine config |
| `inbox-sweep` prompt: channel rule | `inbox-sweep/SKILL.md` | no |
| `meetingVaultPath` + vault interval | Mustard Settings (UserDefaults) | no — app settings |
| `VaultSweep.prompt` fixes (C) | `Sources/MustardKit/Agent/VaultSweep.swift` | **yes — the only code change** |

The non-repo changes (cron, SKILL prompt, app settings) are reversible config; diffs/values shown to Leon before applying. Scheduling `inbox-sweep` means it begins reading Gmail on a timer — an outward, ongoing effect — so it's enabled only on Leon's explicit go-ahead.

## Testing

- `VaultSweep.prompt` is substring-tested (`VaultSweepPromptTests`). Add assertions (TDD) that the prompt contains the channel-rule, enumerate-multi-item, and demote-blocked guidance. (This verifies the *instruction* is present — actual recommendation quality is judged by Leon's live testing, per the project's build+eye rule for prompts.)
- Config changes verified operationally: `inbox-sweep` `lastRunAt` advancing twice daily; meeting tasks appearing in the Inbox; the vault sweep no longer auto-firing between manual runs.

## Note

This realizes the local scout described in ADR-0008 (accepted 2026-06-17) — that ADR decided the *architecture*; this turns it on with a schedule and tunes routing. The earlier "mac-independence deferred" stance is unchanged (still Mac-on, local-only).
