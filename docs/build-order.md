# Mustard — Build Order / Backlog

The backlog as a checked-in file (no external tracker provisioned yet — that's a
gated outward action). Order reflects dependencies. Historical plan docs live in
the sibling Triage-tool repo under `docs/superpowers/plans/`.

## Done ✅

- [x] **F1 Foundation** — SPM package, SwiftData models (Area, TaskList, MustardTask),
      `DayPlanner`, Things-3-calm `Theme`, Today timeline + capture + carry-forward.
- [x] **F2 Agent loop (vault source)** — `ClaudeRunner`, `VaultSweep`, `AgentService`;
      recommend → decide → execute → OutputCard → review.
- [x] **F3 Hover panel** — ⌘⇧H, non-activating; current focus + next-up tasks.
- [x] **F4 Notch surface** — ⌘⇧N; idle rotation (focus → next meeting → waiting),
      hover-expand tray with today's meetings, recs, capture.
- [x] **F5 Scheduled sweeps** — `SweepScheduler`, 60s app loop, Auto-interval menu.
- [x] **F6 Command bar** — ⌘K; capture + navigation + sweep-now.
- [x] **F7 Trust & gating** — `TrustPolicy`, Manual/Supervised/Trusted/Autonomous,
      always-gated outbound actions, lock badges.
- [x] **F8 Personal Kanban board** — status columns, drag-drop, per-column add.
- [x] **F9 Week planner** — Mon–Sun grid, unscheduled rail, drag to (un)schedule.
- [x] **F10 Google Calendar data layer** — `CalendarEvent`, PKCE/OAuth helpers,
      events parser; meetings render on Week + notch.
- [x] **F11 Rich triage cards** — provenance, confidence meter, reasoning, re-bucket
      chips, editable draft, Comment/Snooze/Schedule/Reject; confidence × trust.
- [x] **F12 Task detail editor** — shared sheet (edit/status/owner/estimate/schedule,
      mark done, delete); tap-to-open from Today & Board.
- [x] **F13 Rich task properties** — priority, due, recurrence, tags, blocked-by,
      parent/subtasks (+ estimate); recurrence spawn, subtask cascade, blocked-aware
      next-up, cycle guard. See `task-properties-design.md`.
- [x] **F14 Week planner v2** — Sunsama/Akiflow/Morgen hybrid: per-day time axis
      (8am–6pm) where meetings + *timed* tasks anchor and size by duration
      (resize handle → `estimateMinutes`); untimed tasks list below; per-day
      quick-add; tap-to-detail, check-off, right-click menu; OVERDUE + UNSCHEDULED
      rail; agent tasks in purple. New `MustardTask.isTimed`. Plan:
      `docs/plans/2026-06-14-week-planner-v2.md`.
- [x] **F15 Agent feedback loop** — grounded, action-aware execution prompt
      (uses the proposed draft + action type + source context); a triage Comment is
      fed to the agent on the first run; `revise(card, feedback:)` re-runs with the
      feedback + prior output, producing a new OutputCard with version history.
      `AreaOrganizer`-style pure prompt builder in `VaultSweep`.
- [x] **F16 Areas/Lists organisation UI** — sidebar AREAS section (areas → nested
      lists with open-task counts, an Unfiled bucket), filtered `ListContentView`,
      inline create/rename/delete, **nullify** deletes (organising never loses
      tasks), area-grouped List picker in the detail sheet, list badges on rows.
      Pure `AreaOrganizer` logic.
- [x] **F17 Meeting task ingest** (was B1) — harvest curated `- [ ]` lines from the
      Meeting Sync vault notes into the inbox; two-way completion (tick → note
      checkbox, snapshot-first); vault→Area mapping. Pure `MeetingTaskParser` +
      `MeetingTaskSync` + `FileVaultIO`; provenance fields on `MustardTask`; wired into
      the 60s loop + `meetingVaultPath` Setting. Plan:
      `docs/plans/2026-06-16-meeting-task-ingest.md`.
- [x] **F18 Source-ingestion foundation + triage provenance** — per-source/project
      `SourceSettings`, `InboxIngest` (local `_recs/`), `SourceDedupe`; inert FYI +
      curated-KB `InboxLog`, `originalSource` provenance, `SourceBadge` pill,
      `SourceGrouping` fan-out, `create_task` → real inbox task (PR #13). Specs:
      `docs/specs/2026-06-15-source-ingestion-foundation.md`,
      `docs/specs/2026-06-19-triage-provenance-fyi-and-fanout-design.md`.
      *(The cloud email **scout** that feeds this remains deferred — see N3 / the
      mac-independence spec.)*
- [x] **F19 You → agent delegation** (was I1 ⭐) — "Ask agent to do this" (detail
      sheet + Today/Board/Week context menu) → classify `claude -p` routed by client
      Area (`AreaRouter`) → linked `Recommendation` (`MustardTask.delegation`); trust
      gates run-now (Trusted+) vs queue (`TrustPolicy.shouldAutoRunDelegation`); Accept
      → task done + output appended to Notes; agent may decline; `DelegationPhase`
      status badge. Plan: `docs/plans/2026-06-22-you-agent-delegation.md`.
      *On `feat/you-agent-delegation` — pending merge + Leon's eye-check of the surfaces.*
- [x] **F20 Notes Phase A (BAK-145)** — vault-backed markdown notes: whole-vault
      scanner (`NoteVaultIO`), `WikilinkIndex` link graph, `NoteIndexEntry` SwiftData
      mirror on a 5-min reindex, Notes tab (project sidebar, folder tree, filter),
      raw+preview editor with snapshot-guarded save, backlinks panel, wikilink
      navigation + create-from-unresolved, "+" note creation. Spec:
      `docs/specs/2026-07-05-notes-vault-backlinks-design.md`; plan:
      `docs/superpowers/plans/2026-07-05-notes-phase-a.md`. Phase B (attach to
      tasks/areas, BAK-154) and Phase C (search/tags/rich editor, BAK-155) deferred.
- [x] **F21 Morning ritual (was I5 ⭐, BAK-50 morning half)** — four-step "Plan your
      day" wizard: rollover review (carry-forward now stamps what it moved), inline
      agent standup, pick-today with capacity line, 1–3 focus stars (`focusOnDay`,
      auto-expiring) pinned atop Today + in the notch rotation. Gentle-prompt entry
      (Today banner · notch line · ⌘K), all gated by one pure `RitualPrompt` rule.
      Spec: `docs/specs/2026-07-06-morning-ritual-design.md`; plan:
      `docs/superpowers/plans/2026-07-06-morning-ritual.md`. Evening shutdown
      deliberately deferred (fast-follow once the morning habit sticks).
- [x] **F22 Craft pass — Theme depth/motion + live Notes editor (Notes Phase C)** —
      `Theme.Elevation/Motion/Metrics` + editorial type (with NS bridges), surface
      polish (markdown-rendered task-notes preview, card depth + hover lift, warmer
      empty states), and the live Craft-style editor replacing the Source/Preview
      toggle: TextKit-1 `MarkdownTextView` styling-as-you-type over pure
      `NoteDecoration` spans (no rewrite API — markdown on disk stays truth),
      slash menu (`SlashMenu`), block drag-reorder (`BlockReorder`, byte-pinned),
      hover gutter, subpage cards. Spec:
      `docs/specs/2026-07-06-craft-inspired-notes-and-daily-note-design.md`; plans:
      `docs/superpowers/plans/2026-07-06-craft-pass-phase0-1.md` +
      `…-craft-editor-phase2.md`. Daily Note (spec Phase 3) pinned/deferred.

## Next — buildable, unblocked 🟢 (queued 2026-07-12)

*(Cleared — F23 shipped same-day, see Done.)*

## Done (2026-07-12) ✅

- [x] **F23 Craft editor — full markdown hiding + menu system** — five-phase follow-on
      to F22: shared `BlockKind` model (foundation), fully-hidden markdown syntax
      (Craft-style focus reveal, not just dimming), expanded insert (`/`) menu
      (headings 1-4, quote, lists, code, divider, table, image, sub-page), a "turn
      into" + block-actions context menu, and a floating inline-formatting toolbar
      (bold/italic/strikethrough/code/highlight/link). Color/Indentation/Alignment/
      Page-Card block types/embeds/Mermaid/inline-image-preview explicitly deferred
      (no clean markdown representation). Spec:
      `docs/specs/2026-07-12-craft-editor-menus-design.md`. Linear epic **BAK-248**
      (sub-issues BAK-249..253, phases 0-4) — **all five phases merged 2026-07-12**
      (PRs #91-#95, suite 696 → 835); follow-ups in BAK-254; Leon eye-check pending.

## Done (2026-07-13) ✅

- [x] **F24 Resumable agent task sessions (core MVP)** — Mustard automatically picks up
      delegated tasks, pauses for human answers without blocking the queue, resumes the
      same Claude session, and sends every result to a unified **Needs Review** flow.
      Durable `AgentRun`/`AgentMessage` conversation; provider-neutral `AgentRuntime` with
      the resumable `ClaudeTaskRuntime`; one serial `AgentTaskCoordinator`; pure
      `AgentTaskQueue`/`AgentTaskTransition`/`AgentRetryPolicy`; **Needs You** stage;
      structured worker contract (drafts-only, no send); the file bridge is now reserved
      for explicit `requiresConnectedWorker` fallback only. Task conversation + review UI
      in Task Detail and the Agent Console attention queue. Specs:
      `docs/specs/2026-07-13-agent-task-sessions-design.md`,
      `docs/superpowers/plans/2026-07-13-agent-task-sessions-core.md`. Branch
      `codex/agent-task-sessions-implementation` (suite → 984); **awaiting Leon's hands-on
      test before merge**. Remaining fast-follows: the learning loop
      (`.../2026-07-13-agent-learning-loop.md`), a Codex runtime adapter, parallel
      execution, live token streaming, automatic connected-session launch, and the
      pre-existing iOS shared-view-atom build break (unrelated; tracked separately).

## Next — needs Leon ⛔

- [ ] **N1 Live Google Calendar** — `GoogleAuthSession` (loopback + ASWebAuth) +
      `GoogleCalendarService` (connect/refresh/fetch → upsert) + Keychain + Settings.
      *Blocked on:* Leon's Google Cloud **OAuth client id** (Desktop app).
- [ ] **N2 CloudKit sync + iOS target** — migrate SPM → Xcode project, iCloud
      entitlement, iOS app sharing `MustardKit`. *Blocked on:* Apple Developer
      account / entitlements (Leon).
- [ ] **N3 More sources** — email / Slack as triage sources, via the
      `claude` CLI's MCP config. *Blocked on:* confirming MCP availability + scope.
      *(Meetings split out to B1 — handled by vault-harvest, not MCP.)*

## Next — buildable, unblocked 🟢

- [ ] **F25 Voice capture — push-to-talk → board task → agent cleanup queue**
      *(spec approved by Leon 2026-07-22 — see ADR-0011)*. Hold a global hotkey
      (⌃⌥Space, Carbon `RegisterEventHotKey` — press *and* release, no TCC grant),
      speak, release → task. Three slices:
      - **v1 Capture:** on-device `SFSpeechRecognizer` + `AVAudioEngine` push-to-talk;
        live-transcript pill (HoverPanel pattern, never steals focus); release inserts
        an Inbox task (`.me`, `source = "voice"`, `captureState = .raw`, verbatim
        transcript kept on `captureTranscript`); <300 ms or empty → cancel. Pure
        `VoiceCapture` outcome/normalizer unit (TDD). Info.plist mic+speech usage
        strings in `build-app.sh`.
      - **v2 Cleanup queue:** raw captures batch (≤5) through one `claude -p`
        text-transform pass on the scheduler tick when the execution gate is free —
        title/description/schedule/area auto-applied (tier 1, reversible;
        `normalizePlacement` invariant); 60/300/900 s backoff capped at 3 then
        `.failed` (task stays usable raw). Pure `CaptureCleanupQueue` +
        `CaptureCleanup` prompt/parser/schedule-resolver units (TDD).
      - **v3 Routing:** agent-shaped captures additionally emit a `Recommendation`
        (`source = "voice"`, rec.task = the captured task, action limited to
        draft_email/draft_slack/ticket_write/vault_note) into the existing triage →
        trust → gating → bridge loop. Never sets `owner = .agent` directly (BAK-90 +
        coordinator auto-pickup stay honest).

*(Previous: B1 shipped as **F17**, the multi-source foundation as **F18**, and I1
delegation as **F19**. Other unblocked candidate: **I2 Trust that earns itself** —
design locked 2026-06-16, still needs a plan.)*

## Later — autonomous, unblocked 🔓

- [ ] Gate tuning after real use (`autoConfidenceThreshold`, `isGated`).

## Ideas — brainstormed 2026-06-15, not yet planned 💡

Captured from a brainstorm; each needs its own spec + plan before building.
⭐ = highest-leverage (most advances the "plan your work + your agents' work" wedge).
Intended for Linear later — kept here for now.

**A. Deepen the agent loop**
- [x] **I1 ⭐ You → agent delegation** *(✅ BUILT — shipped as F19, see Done)* — hand a task to the agent from Board/Today
      ("Ask agent to do this"); it enters the existing recommend → approve → execute
      → review pipeline. Completes the currently one-way (agent → you) loop — the
      core of the product thesis.
      *Design decided 2026-06-16 (ready to spec):*
      - **Trigger** is an explicit "Ask agent to do this" action (detail sheet +
        Board/Today right-click) — *not* the assignee toggle.
      - **Classify pass:** delegating fires one `claude -p` that reads the task
        (+ vault) and proposes a Recommendation (`action_type`, draft, confidence,
        reasoning) — same shape as a sweep. Keeps gating honest and yields a draft to
        review/edit. The agent may **decline** ("this needs you") instead of faking output.
      - **Assignee** (`owner`) flips to `.agent` on delegate, back to `.me` on
        reject/discard; otherwise stays a manual label.
      - **Run timing:** trust decides — Manual/Supervised queue the proposal for
        approval; Trusted/Autonomous run immediately; email/Slack/ticket always gated.
      - **Loop close:** execute → OutputCard → **Accept** marks the task done + saves
        output to notes; **Revise** re-runs (F15 feedback loop); **Reject/Discard**
        returns it to you.
      - **Task status** shows *Agent working… → Awaiting review → done*, derived from
        the linked recommendation.
      - **New model bit:** a `MustardTask ↔ Recommendation` link.
- [ ] **I2 ⭐ Trust that earns itself** — track accept/revise/reject history per
      action type; surface the hit-rate ("vault notes: 9/10 accepted") and nudge to
      raise the trust level. Makes the trust ladder feel earned, not static.
      *Design decided 2026-06-16 (ready to spec):*
      - **Metric:** first-pass accept rate per action type (accepted with no revision
        ÷ executed), derived from existing Recommendations/OutputCards — no schema
        change. New pure `TrustCalibration` unit.
      - **Two-stage graduation, user-confirmed + reversible:** Stage 1 = auto-run
        (output still reviewed); Stage 2 = hands-off / auto-accept after a strong
        track record *while* auto-running — but **always still produces an OutputCard**
        (auto-marked accepted, never silent completion).
      - **Guardrails:** min sample (~5) before any nudge; confidence floor still
        applies at both stages; gated types (email/Slack/ticket) never graduate
        (track-record shown but informational).
      - **Symmetric pullback:** accept-rate slips below a floor → nudge to de-graduate.
      - **Override:** a graduated type runs even under Manual/Supervised; the global
        trust level is just the default for un-graduated types.
      - **State:** per-type stage stored in settings, passed into the pure
        `TrustPolicy`/`TrustCalibration` (kept testable).
      - **Surfaced:** "agent track record" strip + nudge banner in the Agent console.
- [ ] **I3 Multi-step agent plans** — agent proposes a stepwise plan, executes with
      checkpoints, one OutputCard per step. For larger delegations.
- [ ] **I4 Diff view on vault edits** — OutputCard shows a before/after diff for note
      changes, not just prose, so you can accept with confidence.

**B. Planning rituals (Sunsama/Akiflow DNA)**
- [ ] **I5 ⭐ Evening shutdown / morning planning** — guided flow: review what got
      done, roll over unfinished, plan tomorrow, set 1–3 intentions — and fold in the
      agent's overnight output + pending reviews. The human+agent daily standup.
- [ ] **I6 Capacity awareness** — sum today's `estimateMinutes` vs available hours;
      gently flag overcommit. (Deferred from the week planner.)
- [ ] **I7 Weekly objectives** — set a few goals for the week, link tasks to them,
      surface on the Week view. Gives the planner a "why". (Deferred from week planner.)

**C. Calm UX refinements**
- [ ] **I8 Natural-language capture** — ⌘K parses "email Sam re: BLE Thursday 2pm"
      into a scheduled task (and could suggest it as an agent draft-email).
- [ ] **I9 Tag filtering / saved smart lists** — tags exist (F13) but aren't
      filterable yet; add filtering + saved views.
- [ ] **I10 Focus mode** — "start" a task → live timer in the notch/hover, everything
      else dims.

