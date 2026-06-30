# BAK-103 — Today: progress bar + Plan entry (+ quick-add already present)

**Run:** 20260701-075733-bak-103-today · **Milestone:** Redesign · Desktop delta
**Risk class:** medium (Sources/ — DayPlanner helper + TodayView + RootView wiring)

## Done
- **Day-progress bar:** thin green fill + "{done} of {total} done" over today's scheduled
  tasks, shown when total > 0. Derived via pure `DayPlanner.dayProgress(_:day:)` (TDD).
- **"✦ Plan with agent"** header button → navigates to the Agent console (TodayView gains
  an `onPlan` callback; RootView passes `{ screen = .agent }`).

## Already present (not rebuilt)
- The "Add a task" affordance is the existing `QuickCaptureField(scheduleOnto: today)`.

## Notes
`DayProgressTests` (pinned UTC) cover done/total derivation incl. other-day exclusion.
