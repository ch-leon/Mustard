# Verification — Morning ritual (BAK-50, morning half)

Run: 2026-07-06 · branch `claude/morning-ritual` · 12 commits over base `ceca506`

## Required checks (.agent-loop/checks.yml)

| Check | Command | Result |
|---|---|---|
| test | `swift test` | **575 tests, 1 skipped (pre-existing), 0 failures** — baseline 556; +19 new across 3 new suites + 3 extended |
| build | `swift build` | **Build complete**, clean |
| app assembly (extra) | `./build-app.sh` | **Built build/Mustard.app** |

## Per-task trail

TDD throughout (red confirmed before green each task); two-stage review per task with
fix rounds: T1 stamps (557) → T2 RitualPrompt (561) → T3 RitualPlanner (569) → T4
notch/⌘K (573) → focus-cap fix (574) → T5 wizard (574, view-only) → plannedToday
extraction fix (575) → T6 entry wiring (575, view-only) → channel-key constant.

New suites: RitualPromptTests (4), RitualPlannerTests (10); extended: DayPlannerTests
(+1 stamp test), NotchTickerTests (+3), CommandBarEngineTests (+1 new, 2 updated
faithfully). All pinned epochs + injected UTC calendars; no ambient clock.

Views (MorningRitualView, TodayView banner/FOCUS, NotchSurface line, CommandBarView
case) are build-verified — Leon's eye-check is the known post-merge step.
