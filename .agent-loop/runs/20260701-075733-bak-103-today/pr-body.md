## BAK-103 — Today: day-progress bar + Plan entry

Adds a thin day-progress bar ("N of M done", derived) and a "✦ Plan with agent" header button that opens the Agent console. The quick-add affordance already existed (QuickCaptureField).

### Changes
- `DayPlanner.dayProgress(_:day:)` (pure, TDD).
- `TodayView`: progress bar + Plan button via a new `onPlan` callback.
- `RootView`: passes `onPlan: { screen = .agent }`.
- `DayProgressTests` (2, pinned UTC).

### Checks
swift build clean · swift test 395 pass / 1 skip / 0 failures (+2).

### Risk
Medium — Logic helper + 2 views; in-app navigation; no schema/outward.
