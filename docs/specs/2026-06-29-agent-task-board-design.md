# Agent Task Board — design spec

- **Date:** 2026-06-29
- **Status:** Draft — awaiting Leon's review
- **Supersedes/affects:** the me-only Board (`PersonalBoard`, `BoardView`), the task status model (`TaskStatus`), the derived `DelegationPhase`, and `OutputCard` review.
- **Visual source of truth:** `~/Downloads/design_handoff_agent_board/` (`Mustard - Board.dc.html`, `MustardBoardCard.dc.html`, `README.md`). The HTML is a reference prototype; recreate it as native SwiftUI. All hex/sizing tokens in that README are exact.

## Why

Mustard's thesis is "plan your work and your agents' work on one surface." Today the Board renders only `owner == .me` tasks; agent work is invisible there, and approving an agent recommendation produces an `OutputCard` in a separate review queue. We are reshaping the Board into the shared work surface: **your tasks and the agent's tasks in one owner-segmented board**, where approving agent work places it in a queue, a decoupled session executes it, and the result returns as a reviewable link.

This replaces the "Approve creates the artifact directly" idea explored earlier. The connector-bound creation (Shortcut/email) **cannot run** in Mustard's headless `claude -p` (scrubbed env, no connectors — ADR-0003), and the DL Shortcut skill needs Google Sheets + a logged-in browser for Jira, which headless also cannot do. So execution is **decoupled**: Mustard stages work; a connected Claude session (a skill you run, or a local routine) does it and writes results back.

## Scope

This spec is **Phase 1 of 3**. Build order:

| Phase | What | Where | This spec |
|---|---|---|---|
| **1. Board + data model** | Owner-segmented board, the stage/owner/links model, and the entry wiring (console-approve → Queued; create → For Agent) | Mustard (SwiftUI + SwiftData) | **In scope** |
| 2. The bridge | Mustard exports queue columns to vault files + ingests result files (reuses the `_recs/` → InboxIngest pattern) | Mustard | Out of scope (sketched only) |
| 3. The worker | The skill/routine that reads the queue, runs the full DL skill with connectors, writes results back | DL vault side | Out of scope |

**Explicitly out of scope for Phase 1:** real execution of any agent task; the Gmail/Xero/Slack/Linear sources shown in the mock (illustrative only — real sources are vault, meeting, and the Gmail scout); an autonomous tier that auto-creates drafts without Approve; live "running" progress (cut — see below).

## The pipeline

Every task has a single `stage`. There is one `owner` (`me` / `agent`). Stages:

| stage | label | column kind | belongs to |
|---|---|---|---|
| `inbox` | Inbox | default | shared (untriaged) |
| `planned` | Planned | default | me |
| `scheduled` | Scheduled | default | me |
| `forAgent` | For Agent | handoff | agent |
| `needsApproval` | Needs Approval | gate | agent |
| `queued` | Approved · Queued | agent | agent |
| `needsReview` | Needs Review | gate | agent |
| `inProgress` | In Progress | default | me |
| `blocked` | Blocked | warn | me |
| `done` | Done | done | shared |

`running` from the mock is **removed** — execution is decoupled, so there is no live progress for Mustard to show. A queued item simply reappears in `needsReview` after a session runs it.

`someday` from today's model is **dropped** (acceptable data loss per Leon).

### Two ways work reaches the agent's queue

**Path A — Agent proposes (sweeps).** Email/vault/other sweeps produce **recommendations** in the Agent console (existing triage). They are NOT on the board. Triaging there:
- **Approve** → promote to a task at stage `queued`, `owner = agent`.
- **Schedule** → a `scheduled` task, `owner = me`.
- **Reject / Snooze / etc.** → unchanged (stay in the console).

Recommendations never seed the board Inbox.

**Path B — You delegate (manual).** You capture a task (lands in `inbox`, `owner = me`) and move it to `forAgent`. A **prep** session picks it up, fleshes out the draft/details, and moves it to `needsApproval`. You approve → `queued`.

### Execution (decoupled — Phase 2/3)

An **execute** session/routine pulls from `queued`, performs the action, and writes the result into `needsReview` carrying **links** (Shortcut URL, Jira URL, email-draft link, …). You eyeball it and move it to `done`. For now `needsReview` is a **log/validation column**, not a hard gate — it exists so you can confirm the agent did the right thing; it may be removed later.

**Routing by action type:** not everything needs the connected session.
- In-vault actions (`vault_note`, `create_task`) can run **headless** (Mustard already can) → straight to `done` (or no board task at all for `create_task`).
- Outward/connector actions (`ticket`/Shortcut, `draft_email`, `draft_slack`) → `queued` → connected session → `needsReview`.

The task's `actionType` decides the route and the gating padlock.

## Views

The owner segmented control (`Everyone` / `Mine` / `✦ Agent`) changes which columns are visible. **Inbox and Done are shared and appear in all three views** (you triage and route from Inbox regardless of which lens you're in).

- **Everyone:** `inbox, planned, scheduled, forAgent, needsApproval, queued, needsReview, inProgress, blocked, done`
- **Mine:** `inbox, planned, scheduled, inProgress, blocked, done`
- **Agent:** `inbox, forAgent, needsApproval, queued, needsReview, done`

View switching is a pure view change; it does not mutate data. Area filters (sidebar rows + chips) combine with owner via AND. `personal` = `errands` ∪ `reading`.

## Data model

Source of truth shifts from `status` + derived `DelegationPhase` to a single `stage`.

`MustardTask` changes:
- **Add `stage: TaskStage`** (the 10 values above) as the task's lifecycle field. **Remove `status: TaskStatus`** (migrate values: `inbox→inbox`, `planned→planned`, `inProgress→inProgress`, `done→done`, `someday→` dropped; scheduling presence (`scheduledAt != nil`) → `scheduled`).
- **Keep `owner: TaskOwner`** (`me`/`agent`).
- **Add `links: [TaskLink]`** where `TaskLink = { label: String, url: String }` — populated on `needsReview` (Shortcut/Jira/draft). Stored as a small Codable list (SwiftData attribute), not a relationship.
- **Add `actionType: RecommendationAction?`** — drives gating + the headless-vs-connector route. Nil for ordinary personal tasks.
- **Add `confidence: Double?`** — shown on `needsApproval` / proposed cards.
- **Derive `isGated`** from `actionType` (reuse `RecommendationAction.isGated`); not stored.
- Existing `delegation: Recommendation?` retained for provenance.

`Recommendation`: unchanged as the upstream sweep entity. Approving promotes it into a `queued` task (carry over `title`, `draft`→notes, `actionType`, `confidence`, `source`, link the task via `delegation`).

`OutputCard`: **retired.** Its review role is replaced by the `needsReview` stage + `links`. Migration: existing pending/accepted cards can be dropped (acceptable data loss) or, if simpler, left orphaned and ignored by the new UI. `DelegationPhase` logic is removed (stage is now explicit).

`PersonalBoard`: rewritten to bucket by `stage` (not `status`) and to return the correct column set per `owner` view. The current `owner == .me` hard filter is removed; filtering is by the selected view.

## Board UI

Recreate the prototype faithfully in SwiftUI using `Theme` tokens where they exist and the exact hex from the handoff README where they don't. Key pieces:

- **Sidebar (208px):** nav (Today/Board/Week/Agent) with the agent badge = count of `needsApproval` + `needsReview` across all tasks; AREAS section driving the area filter.
- **Header:** title, the **"N waiting on you"** pill (= `needsApproval` + `needsReview` within the current filtered scope; hidden at 0), Search + New task (Search/New may be stubbed in Phase 1), the owner segmented control, area chips, and the per-view caption.
- **Columns:** width 182px (compact 162px), styled by `kind` (default/handoff/gate/agent/warn/done) per the README's color table; each column body scrolls independently; empty shows "—"; per-column "+ Add".
- **Card (`MustardBoardCard`):** owner toggle (`You`/`✦`), `✦ Proposed` pill, gated padlock, title, meta (area swatch+name, source badge, due pill), confidence (score + 5 bars, thresholds per README) on `needsApproval`/proposed, status pill per stage, blocked reason. Done cards dimmed + strikethrough. Left accent border: amber if blocked, else agent-purple if `owner == agent`. The `✦` agent mark maps to a single consistent SF Symbol.
- **Drag:** column-to-column drag sets a task's `stage` (the mock left this unimplemented; implement it).
- **Card owner toggle:** to agent → `forAgent`; to me → `planned`; done keeps its stage; clear `proposed`.

## Settings

Map the prototype's three props to user settings: `defaultView` (everyone/me/agent), `density` (normal/compact), `showConfidence` (bool).

## Testing (TDD per CLAUDE.md)

Pure logic, tests first:
- `PersonalBoard` bucketing: each view returns the right column set; tasks bucket into the right column by `stage`; area+owner filters combine (AND); `personal` = errands ∪ reading.
- Stage transitions: drag `move(task, to:)`, owner-toggle reassignment rules, console-approve → `queued` promotion, create → `forAgent`.
- Derivations: `isGated` from `actionType`; "waiting on you" count (scoped) vs agent badge (global); confidence segment count + threshold colors.
- Migration: `status` → `stage` mapping incl. `scheduledAt`-implies-`scheduled` and `someday` drop.
Views verified by `swift build` + Leon's eye (no UI unit tests).

## Open questions / risks

- **CLI auth:** the `claude` CLI OAuth token expired 2026-06-09; all headless runs 401 until `claude setup-token`. Independent of Phase 1, but blocks Phase 3 (and likely means current sweeps are failing). Mustard should surface "CLI auth expired" as a first-class error (separate small fix).
- **Bridge format (Phase 2):** exact file shape for the `queued`/`forAgent` export and the result import — to be specified in the Phase 2 spec. Reuse `_recs/` conventions.
- **Prep vs execute sessions (Phase 3):** one routine doing both passes, or two? Deferred to Phase 3.
- **`needsReview` longevity:** kept as a validation/log column for now; revisit removing it once trust in the agent output is established.
