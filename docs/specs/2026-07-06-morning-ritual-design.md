# Morning ritual — plan your day with the agent — design spec

- **Date:** 2026-07-06
- **Status:** Approved (2026-07-06) — brainstormed with Leon question-by-question; see Decision log
- **Tracker:** BAK-50 (becomes the epic for this build; evening-shutdown half re-scoped out — see Scope)
- **Supersedes/affects:** makes Today's silent `DayPlanner.carryForward` *visible* (stamps what it moved; behavior otherwise unchanged); adds two optional fields to `MustardTask`; adds a new `MorningRitualView` sheet, `Logic/RitualPlanner.swift`, `Logic/RitualPrompt.swift`, a Today banner, a notch idle-rotation line, and a ⌘K command. Nothing existing is removed.

## Why

Build-order I5 ⭐ / BAK-50: the Sunsama-DNA daily ritual is the biggest untouched piece
of the product thesis — "plan your day and your agents' day together." Today already
has the ingredients (merged agenda, carry-forward, unscheduled inbox, agent nudge) but
no *ritual*: carry-forward is silent, agent triage is a separate habit that can rot,
and nothing makes the day's plan deliberate.

Leon ranked the ritual's jobs (2026-07-06): **deliberate day planning**, **agent
standup habit**, and **intentions/focus** — explicitly *not* evening bookend
reflection, which is why this spec is morning-only.

## Scope

**In:** the four-step morning wizard (below), its entry points (Today banner, notch
idle line, ⌘K), the two `MustardTask` fields, focus pinning on Today, focus in the
notch rotation.

**Out (explicitly, per brainstorm):** evening shutdown flow (fast-follow once the
morning habit sticks — remains on BAK-50's history), free-text intentions, streak/
history tracking, forced full-screen takeover, weekly objectives (I7), natural-language
capture (I8), and **mobile ritual UI** — the Logic + model fields land in shared
MustardKit so iOS inherits the data per the parity rule, but the mobile flow is a
separate later slice.

## Design decisions (from the brainstorm, in order)

1. **Purpose** — deliberate planning + agent standup + intentions; not evening reflection.
2. **Entry** — gentle prompt: a calm Today banner (agent-nudge treatment) + notch idle
   line + ⌘K "Plan my day". Never a takeover; ignorable without guilt; dismiss = gone
   for the day.
3. **Agent step** — inline mini-triage embedded in the flow (not a console handoff,
   not summary-only): approve/reject/snooze/I'll-do-it per rec without leaving the
   ritual, reusing `AgentService.decide`/`snooze`.
4. **Intentions = starred tasks** — mark 1–3 of today's tasks as THE focus; no
   free-text to maintain. Pinned atop Today; surfaces in the notch focus rotation;
   done-state is automatic.
5. **Morning-only** — evening shutdown deferred (rollover review happens next morning
   anyway).
6. **Form = guided wizard** — a four-step sheet over Today with a clear finish, each
   step skippable. Chosen over a Today "planning mode" (crowded, mode-muddy) and a
   minimal no-flow composite (abandons the habit-forming ritual).

## Architecture

**Pure logic (TDD'd, no FS/clock/SwiftData in decisions):**

- `Logic/RitualPlanner.swift` — computes each step's content from in-memory inputs:
  - `rollover(_ tasks:, day:, calendar:)` → open tasks whose `carriedForwardAt` falls
    on `day` (what the silent carry-forward moved this morning).
  - `standup(_ recs:)` → pending, un-snoozed recommendations (mirrors the console's
    pending filter), plus the Needs Review count from tasks.
  - `pickCandidates(_ tasks:)` → unscheduled open tasks (the inbox), excluding
    anything already planned today.
  - `plannedMinutes(_ tasks:, day:)` → sum of today's `estimateMinutes` for the
    passive capacity line (reuses the Week capacity thresholds/tiers).
  - `focusLimit = 3`; `toggleFocus`-style pure helpers validating the cap.
- `Logic/RitualPrompt.swift` — `shouldOffer(lastPlannedDay: Date?, dismissedDay:
  Date?, now: Date, calendar:) -> Bool` (true when neither is `now`'s day). One rule,
  consumed by the banner, the notch line, and the ⌘K command's visibility.

**Views (render + dispatch only):**

- `Views/MorningRitualView.swift` — the sheet: step rail (1 Rollover · 2 Agent ·
  3 Pick · 4 Focus), progress bar, Back / Skip step / Continue, final "Start the day".
  Steps dispatch to existing engines: task `scheduledAt`/`focusOnDay` mutations and
  `AgentService.decide`/`snooze`. No claude invocations anywhere — the whole ritual
  is local and instant.
- `Views/TodayView.swift` — the entry banner (agent-nudge visual treatment) when
  `RitualPrompt.shouldOffer`; focus tasks pinned in a "FOCUS" group above the
  timeline with a star glyph; `DayPlanner.carryForward` call unchanged.
- Notch: when `shouldOffer`, the idle rotation gains a "Plan your day ✦" line; once
  planned, `NotchTicker`'s existing focus slot prefers the first *open* focus task
  (falling back to its current pick when none are starred). Exact `NotchTicker` API
  wiring is a plan-phase detail; the selection rule itself is pure and tested.
- `CommandBarEngine`: `.planDay` kind + "Plan my day" item → opens the ritual.

**State:** `lastPlannedDay` + `ritualDismissedDay` in `UserDefaults` (stored as
`timeIntervalSince1970` of `startOfDay`, matching existing settings style — ADR-0001
defers a settings model). Completing OR skipping-to-the-end stamps `lastPlannedDay`.

## Data model

Two optional, defaulted-nil fields on `MustardTask` (CloudKit-safe, ADR-0001):

- `carriedForwardAt: Date?` — stamped by `DayPlanner.carryForward` when it moves a
  task (the only behavior change to carry-forward: it records what it did). Lets the
  rollover step show *exactly* what rolled today, without changing when/how tasks move.
- `focusOnDay: Date?` — startOfDay the task is starred for. "Starred today" =
  `focusOnDay` is today, so stars expire naturally at midnight; no cleanup pass, no
  separate model.

No new `@Model`. No ritual-history persistence (out of scope).

## The four steps

1. **Rollover** — list of tasks carried onto today this morning. Per row: **Keep
   today** (no-op) · **Tomorrow** (scheduledAt +1 day, keep time) · **To inbox**
   (clear scheduledAt). "Keep all" one-tap affordance. Empty state: "Nothing rolled
   over — clean slate." skips straight past.
2. **Agent standup** — compact rec rows (source badge, confidence, title): Approve ·
   I'll do it · Snooze · Reject, via `AgentService`. Needs Review count with "Open
   in console →" (closes the sheet onto the Agent tab). Edit/Comment intentionally
   stay in the console. Empty state: "Nothing from the agent overnight."
3. **Pick today** — inbox candidates with tap-to-add (sets `scheduledAt` = today,
   untimed) and tap-to-remove for today's already-planned; passive capacity line
   ("~4h 30m planned") reusing the Week capacity calc/tiers — informational only,
   no blocking.
4. **Focus** — today's planned tasks; tap stars up to 3 (`focusOnDay = today`);
   4th tap is refused with a calm hint. Finish → "Start the day" lands on Today
   with the FOCUS group pinned.

Every step has Skip; Back navigates freely; closing the sheet mid-way stamps nothing
(banner persists until finished or dismissed).

## Failure/edge behavior

- Ritual never run → today behaves exactly as before this spec (carry-forward still
  silent-but-stamped; no nags beyond the one banner).
- Rec decided elsewhere mid-ritual (e.g. auto-trust) → step list is @Query-driven,
  rows simply disappear; no double-decide (decide is idempotent per rec state).
- Day flips while the sheet is open (planning at 23:59) → accepted cosmetic edge:
  content keys off the day captured at sheet open.
- `estimateMinutes` absent on most tasks → capacity line hides below a minimum
  (only shows when ≥1 estimated task), avoiding a misleading "0m planned".

## Testing (per CLAUDE.md)

Pure, fixtures, pinned `Date(timeIntervalSince1970:)`/UTC calendars:
- `RitualPlannerTests` — rollover selection (stamp-today vs stale stamps vs unstamped),
  standup filter parity with the console's pending rule, pick candidates, planned-
  minutes summation + hide-threshold, focus cap.
- `RitualPromptTests` — nil/today/yesterday matrix for both stamps; midnight boundary.
- `DayPlannerTests` (extend) — carryForward stamps `carriedForwardAt` on moved tasks
  only.
- `CommandBarEngineTests` (extend) — new item present.
Views build-verified + Leon's eye (sheet, banner, FOCUS pinning, notch line).

## Decision log

Brainstormed with Leon 2026-07-06 via one-question-at-a-time multiple choice; every
fork above records his pick. The wizard mockup (step 2 shown) was presented inline
before the form decision. Evening shutdown was consciously deprioritized by Leon in
the purpose question — recorded here so the fast-follow starts from that context.
