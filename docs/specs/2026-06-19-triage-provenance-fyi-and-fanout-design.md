# Triage upgrades — inert FYI, curated KB, email source + fan-out

**Status:** Designed (2026-06-19) — open questions resolved; awaiting final spec sign-off before plan.
**Date:** 2026-06-19
**Related:** ADR-0008 (local-only email scout), ADR-0006 (confidence × trust gating),
ADR-0001 (SwiftData + CloudKit, no backend), `2026-06-17-email-scout-and-mac-independence.md`,
`docs/scout-routine-prompt.md`.

## Why this note exists

Reviewing real recommendations, Leon hit three rough edges in the triage loop:

1. **Approving an FYI is wasteful.** It spends a `claude -p` run to reword the draft into
   an `OutputCard` that then sits in the review queue — for an item whose whole point is
   "I read it, I'm aware." (`AgentService.decide` → `execute`, `VaultSweep.directive(.fyi)`.)
2. **Email provenance is lost.** An email surfaced as a recommendation reads as `VAULT`,
   not Gmail, and the original email can't be read before the proposed draft. The model
   *already* supports `SourceID.gmail` + `sourceURL`/`sourceContext`/`occurredAt`
   (`SourceProposal`), but the email is being laundered through the vault by an external
   email→KB routine, and the scout is told to **summarize, no raw bodies**
   (`docs/scout-routine-prompt.md`).
3. **One email collapses into one action.** `Recommendation.proposedActionType` is a single
   enum, so an email that implies *both* a reply and a follow-up task gets mis-bucketed as
   a single (often `fyi`) rec.

This spec fixes all three and locks the curated-KB model that ties them together.

## Decisions locked this session

- **Curated KB.** The external email→KB firehose is turned **off** (operational, Leon's
  side). Email arrives only as first-class `gmail` recs via the scout's `_recs/`
  (already wired: `InboxIngest` + the app loop, `MustardApp.swift:58`). The KB stores
  **only what Leon explicitly Keeps**.
- **Fan-out display = Option A** (group-by-source). No new `@Model`; pending recs that
  share a `sourceItemID` render under one source header. Option B (a persisted
  `SourceItem` entity) is explicitly deferred — durability is covered by Keep → KB.
- **FYI stays** as a bucket; acknowledging it does nothing (no Claude, no review card).

## Feature 1 — FYI acknowledge is inert

**Behaviour.** For a `.fyi` recommendation:
- Acknowledging runs **no `claude -p`** and creates **no `OutputCard`**. The rec simply
  leaves the pending queue (which filters `decision == .pending`).
- Outcome buttons for `.fyi` change from `Approve / Reject` to **Keep** and **Dismiss**
  (re-bucket chips stay):
  - **Keep** → append the item to the KB rolling log (Feature 2), set `decision = .approved`.
    This is the *only* path an FYI's content enters the KB now that the firehose is off.
  - **Dismiss** → set `decision = .denied`. Nothing stored, hard-gone (not snooze-able).
  - (Label note: "Keep" may be renamed "File" / "Save to KB" — pending Leon's word choice.)

**Touchpoints.**
- `AgentService.decide(_:_:)` — guard: if `rec.action == .fyi`, never call `execute()`.
- `AgentService.keep(_:)` — new: write the KB note (shared writer, Feature 2) + set terminal decision.
- `AgentConsoleView.RecommendationRow.outcomes` — action-aware button set for `.fyi`.

**Tests.** `decide(.fyi, .approved)` and `keep(fyiRec)` make **zero** `ClaudeRun` calls
(stub asserts not called) and create **zero** `OutputCard`s; `keep` writes one note,
`dismiss`/`.denied` writes none.

## Feature 2 — Curated KB

**KB rolling-log writer.** Kept items **append to a single rolling log**,
**`<workingDirectory>/_filed/inbox-log.md`** (one log per project). A pure function
produces the markdown **entry** from a rec (timestamp, source, `sourceURL` thread link,
title, body/`originalSource`); `AgentService` appends it (creating the file if absent).
Entry shape, e.g.:

```markdown
## 2026-06-19 14:32 · Gmail · Ruby Giddings — Pre-workshop error screens
[thread](https://mail.google.com/…)

<body / original email excerpt>

---
```

**Loop mitigation (load-bearing).** The vault sweep currently reads the *whole* directory
with no exclusions (`VaultSweep.prompt`), so a filed note would be re-proposed on the next
sweep — an infinite loop. Two guards, both required:
- Write filed notes under `_filed/` (a dedicated subfolder, never the KB root).
- Add an explicit ignore line to `VaultSweep.prompt`: *ignore `_filed/`, `_recs/`,
  and `.obsidian/`.* (`_recs/` is the scout's drop folder — already conceptually ignored
  per `docs/scout-routine-prompt.md`, but not in Mustard's own sweep prompt.)

**Firehose off.** Operational prerequisite, not code: Leon disables the external
email→KB-note routine. After this, emails reach Mustard only as `gmail` recs.

**Tests.** The appended log **entry** markdown is deterministic for a fixed rec (pure,
time/timezone injected per the TDD rules). A filed path is excluded by the sweep's ignore
set (path-filter helper rejects `_filed/...`).

## Feature 3 — Email as source + fan-out (Option A)

### 3a. Provenance pill
Upgrade the grey `rec.source.uppercased()` line in `RecommendationRow.provenanceLine` to an
icon + pill. A pure mapping `SourceID → (SF Symbol, label, tint)`:
- `.gmail` → envelope icon, "Gmail", a Gmail-red accent; keep the existing `Open ↗` link to `sourceURL`.
- `.vault` → book icon, "Vault", tertiary/quiet.

### 3b. Original email
- Add `originalSource: String?` (optional, nil default → CloudKit-safe per ADR-0001) to
  `Recommendation` and to `SourceProposal` (Codable; `InboxIngest` decodes it automatically).
- **Scout prompt change** (`docs/scout-routine-prompt.md`): include the raw email body in
  `originalSource` for `gmail` recs (reverses today's "no raw bodies"). Safe for dedupe —
  gmail identity is the message id (`sourceEventID`), not a content hash.
- **UI:** a collapsible **"Original email"** in the `RecommendationRow` drawer, rendered
  **above** `PROPOSED DRAFT`, so the source is read before the draft.

### 3c. Group-by-source view
- A pure grouping function (`Logic/`): `group(_ recs: [Recommendation]) -> [RecGroup]`,
  where a `RecGroup` is a shared-source header + its member recs. Recs grouped when they
  share a non-empty `sourceItemID` **and** there are ≥2; otherwise a singleton group
  (renders as today — vault recs hash to unique ids, so they stay ungrouped).
- `AgentConsoleView` renders the source header (provenance pill + collapsible original
  email) once per multi-member group, with each member rec's full triage row beneath it.
  Each action is triaged independently (approve one, snooze another).

### 3d. `create_task` materialises a real task
Folds in the gap found earlier: approving a `create_task` rec must put a real task into
the planner (today it only produces a review card).
- **Behaviour (confirmed 2026-06-19):** approving `create_task` inserts a `MustardTask`
  (`title = rec.title`, `notes = draft || body`, `status = .inbox`, `owner = .me`)
  **directly — no `claude -p`, no `OutputCard`.** The task appearing in the Board inbox is
  the feedback. Mirrors the existing "I'll do it" button.
- Touchpoint: `AgentService.decide`/`execute` branch on `.createTask`.

**Tests.** Grouping function: fixtures with shared/!shared `sourceItemID` produce expected
groups, order stable. `originalSource` round-trips through `SourceProposal` decode.
Approving a `create_task` rec creates one `MustardTask` (expected fields), **zero**
`ClaudeRun` calls, **zero** `OutputCard`s. Provenance mapping is pure + covered.

## Sequencing

Ship smallest blast-radius first; 1 and 2 share the KB writer:
1. **Feature 1** (inert FYI) + the shared KB-note writer.
2. **Feature 2** (curated KB: `_filed/`, sweep ignore). Firehose-off in parallel (Leon).
3. **Feature 3** (provenance pill → original email → grouping → `create_task` task).

## Data-model summary (CloudKit-safe)

- `Recommendation`: **+ `originalSource: String?`** (optional, nil default).
- `SourceProposal`: **+ `originalSource: String?`** (Codable, defaulted).
- **No new `@Model`** (Option A). No migration beyond the additive optional field.

## Out of scope (YAGNI)

- Option B `SourceItem` entity — revisit only if grouping proves too thin.
- Sending email/Slack/tickets — still **draft-only** (unchanged).
- Mac-independence / mobile triage — still deferred (ADR-0008).
- Auto-fan-out heuristics beyond what the scout prompt produces.

## Resolved (spec review 2026-06-19)

1. **`create_task` on approve** → insert `MustardTask` to the **Inbox** directly; no Claude
   run, no review card (Feature 3d).
2. **Keep → KB** → **append to a rolling log** `_filed/inbox-log.md` (timestamp · source ·
   thread link · title, then body); not one-note-per-item (Feature 2).
3. **Dismiss** → **hard-gone** (`decision = .denied`); not snooze-able. "Keep"/"Dismiss"
   labels stand, with "Keep" possibly renamed "File"/"Save to KB" (Leon's word, pending).
4. **Vault provenance pill** → **badge non-vault sources only**; vault stays quiet.

## ADR follow-up

Record the **curated-KB** decision (emails as `gmail` recs; KB stores only Kept items;
external firehose retired) as a short ADR or an update to ADR-0008's consequences.
