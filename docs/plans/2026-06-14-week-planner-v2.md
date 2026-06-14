# Plan — Week Planner v2 (Sunsama/Akiflow/Morgen hybrid)

**Status:** awaiting Leon's approval (Plan gate).
**Branch:** `claude/weekly-planning-view-gxtp0h`
**Builds on:** F9 (`WeekPlanner` + `WeekView`), F10 (`CalendarEvent`), F12 (`TaskDetailSheet`).

## Goal

Level the existing Mon–Sun grid up from a per-day task *list* into a real
planning surface, in the spirit of Sunsama (ordered day columns, planned day)
and Akiflow/Morgen (time-blocking on an axis) — without losing the Things-3-calm
feel.

## Decisions (from Leon, 2026-06-14)

| Area | Decision |
|------|----------|
| Layout | **Hybrid** — meetings + *timed* tasks anchor to a light time axis; *untimed* tasks flow as an ordered list below the axis. |
| Time axis | Visible **8am–6pm**, **30-min** grid. Items outside the window still render in the list below. |
| Time-blocking | Blocks **sized by duration** (meeting: end−start; task: `estimateMinutes`) and **resizable** via a bottom handle → updates `estimateMinutes`, snapped to 30 min. |
| Drag | **Assigns the day only** (keeps time-of-day; 9:00 default). Precise time is set in Task Detail. |
| Inline actions | Tap → detail · check-off complete · quick-add per day · right-click context menu. |
| Overdue | Open *my* tasks scheduled before today are **pulled into the rail** under a separate `OVERDUE` section (above `UNSCHEDULED`); they no longer render on their past day. |
| Agent work | Scheduled **agent-owned** tasks render on the grid in **agent-purple**. |
| Today | Highlight today's **column** (no now-line, no auto-scroll). |
| Out of scope | Weekly goals/objectives panel; capacity/planned-time tally. |

## Model change

`MustardTask` gains:

```swift
public var isTimed: Bool = false   // false = planned for the day (list); true = anchored to a time on the axis
```

Default `false` → automatic lightweight SwiftData migration; existing scheduled
tasks become untimed (flow in the list). Set `true` when a specific time is
chosen in Task Detail; set `false` when dragged onto a day from the rail.

## Logic (TDD — `WeekPlanner`, tests first)

New / changed pure functions, each with a pinned-UTC test:

1. `overdue(_:now:calendar:) -> [MustardTask]`
   Open, `.me`-owned tasks with `scheduledAt` strictly before `startOfDay(now)`.
   Excludes today/future, `.done`, `.someday`, and agent tasks. Sorted oldest-first.
2. `tasks(on:now:calendar:)` — extend the existing `tasks(on:)` to **exclude
   overdue open `.me` tasks** (they live in the rail now). Done tasks, today/future
   tasks, and agent tasks still render on their day.
3. `snapDuration(_ minutes:snap:min:) -> Int` — snap a dragged duration to the
   30-min grid with a floor (used by the resize handle).
4. `minutesSinceDayStart(_:dayStartHour:calendar:) -> Int` — pure axis math for
   positioning a timed block (view multiplies by points-per-minute).

`days`, `unscheduled`, `scheduleDate` are unchanged.

## View (`WeekView` — build + Leon's eye)

Per day column, top→bottom:
- **Header**: weekday + day number; today gets the existing blue emphasis. Column
  background tint stays for today.
- **Time axis** (8am–6pm, faint 30-min hairlines): meetings and `isTimed` tasks
  whose time falls in-window are absolutely positioned by start, height ∝ duration.
  Task blocks get a bottom **resize handle** → `estimateMinutes` via `snapDuration`.
  Block colour: meeting = surface; my task = accent-blue; agent task = agent-purple.
- **List below**: untimed tasks + any timed item outside the window, as compact
  chips (current `WeekBlock` look), draggable.
- **Quick-add**: a `QuickCaptureField(scheduleOnto: day)` at the bottom → creates an
  **untimed** task on that day (`isTimed = false`, `status = .planned`).

Interactions:
- **Tap** any task block/chip → `TaskDetailSheet` via a `selectedTask` sheet
  (mirrors `TodayView`).
- **Check-off**: leading checkbox toggles done (reuses the `toggle` pattern).
- **Right-click menu** on a task: Complete/Reopen · Unschedule · Open detail · Delete.
- **Drag**: rail→day schedules untimed (keeps current drop behaviour, sets
  `isTimed = false`); day→rail unschedules; day→day keeps time-of-day + `isTimed`.

Rail (left):
- `OVERDUE` section (from `WeekPlanner.overdue`) — only shown when non-empty;
  chips draggable onto days.
- `UNSCHEDULED` section (unchanged).

`QuickCaptureField` gets an `isTimed` consideration: the per-day capture sets the
task untimed (it already sets `scheduledAt` 9:00 + `.planned`; we add `isTimed = false`,
which is the default, so no change needed there — captured tasks are untimed).

## Tests

- Extend `WeekPlannerTests` with: `overdue` (filtering + ordering),
  `tasks(on:now:)` excludes overdue but keeps done/agent/future, `snapDuration`,
  `minutesSinceDayStart`. Keep the existing 6 green.
- Views verified by `swift build` + Leon's confirmation (no TCC screenshots).

## Build-order entry

Add **F13 Week planner v2** to `docs/build-order.md` once approved.

## Sequencing

1. Tests for new `WeekPlanner` funcs (red).
2. `MustardTask.isTimed` + `WeekPlanner` funcs (green).
3. `WeekView` rebuild: rail (overdue+unscheduled), day column (axis + list +
   quick-add), blocks (colour by owner, resize handle), tap/check/context-menu.
4. `TaskDetailSheet`: set `isTimed = true` when a time is picked.
5. `swift test` + `swift build`; commit in bite-sized steps; push; draft PR.
