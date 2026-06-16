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

## Next — needs Leon ⛔

- [ ] **N1 Live Google Calendar** — `GoogleAuthSession` (loopback + ASWebAuth) +
      `GoogleCalendarService` (connect/refresh/fetch → upsert) + Keychain + Settings.
      *Blocked on:* Leon's Google Cloud **OAuth client id** (Desktop app).
- [ ] **N2 CloudKit sync + iOS target** — migrate SPM → Xcode project, iCloud
      entitlement, iOS app sharing `MustardKit`. *Blocked on:* Apple Developer
      account / entitlements (Leon).
- [ ] **N3 More sources** — email / Slack / meetings as triage sources, via the
      `claude` CLI's MCP config. *Blocked on:* confirming MCP availability + scope.

## Later — autonomous, unblocked 🔓

- [ ] Gate tuning after real use (`autoConfidenceThreshold`, `isGated`).

## Ideas — brainstormed 2026-06-15, not yet planned 💡

Captured from a brainstorm; each needs its own spec + plan before building.
⭐ = highest-leverage (most advances the "plan your work + your agents' work" wedge).
Intended for Linear later — kept here for now.

**A. Deepen the agent loop**
- [ ] **I1 ⭐ You → agent delegation** — hand a task to the agent from Board/Today
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

