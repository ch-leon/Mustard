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
- [ ] Areas/Lists organisation UI (models exist; no UI yet).
- [ ] Evening shutdown / morning planning ritual (Sunsama-style).
- [ ] Re-run-with-comment (feed a Recommendation's comment back into a re-sweep).
