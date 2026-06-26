# Agent recommendations — master-detail + auto-open source — design

- **Date:** 2026-06-24
- **Status:** Approved (design); ready for implementation plan
- **Scope:** The Agent console's `RECOMMENDATIONS` queue only. Turn today's click-`Review`-to-expand-inline into a master-detail layout (selected rec → detail on the right), and add a setting that controls whether the **source panel auto-opens** on selection.
- **Depends on:** the in-app source panel (`SourcePanelController`, `SourceLink`, `SourcePanelView`) — currently in PR #20 (`feat/in-app-source-panel`), not yet merged.

## Problem & context

Today, a recommendation in `AgentConsoleView` is a row that expands **inline** when you click `Review`, revealing the triage drawer (why · re-bucket chips · original source · editable draft · comment) and the action row. Reviewing several recs means expanding/collapsing in place.

Leon wants a **master-detail** layout instead: the selected recommendation's detail opens in a pane on the right. The in-app **source web inspector** (built in #20, a trailing `.inspector` toggled by ⌘⇧S or a row's source glyph) also lives on the right. The two are different content — the detail is the *triage workspace*; the source view is the *external page* — and the resolved design is **Model B (both visible side by side)**, with the source panel's **auto-open** gated by a setting so it can be silenced if the web view popping open as you move through recs becomes distracting.

## Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Master-detail replaces inline expand** | Selecting a rec opens its detail on the right. The `Review`/`Hide` toggle and the inline drawer are removed — selection does the work. |
| 2 | **Detail + source coexist (Model B)** | Detail is the middle-right pane; the source inspector composes on the trailing edge (built in #20). Layout becomes `sidebar │ rec-list │ rec-detail │ [source]` — 3 columns normally, 4 when a source is open. |
| 3 | **Setting: "Auto-open source when I select a recommendation"** (default **on**) | When on, selecting a rec that has a source also calls `sourcePanel.open(link)`. When off, the source panel only opens via the glyph / ⌘⇧S. This is the toggle Leon asked for — it silences the auto-popping web view without affecting detail-on-select. |
| 4 | **Sourceless selection leaves the source panel as-is** | Selecting a rec with no web source (e.g. a vault rec) does not re-point or empty the panel — it only re-points when the selected rec actually has a `SourceLink`. Avoids an empty flash. |

## Behavior

- **Selection:** clicking a recommendation row selects it (clear selected-row highlight) and shows its detail on the right. On arrival, the **first pending rec is auto-selected** so the detail pane isn't empty.
- **Detail pane** shows, for the selected rec, exactly what the inline drawer + action row show today: the provenance line, action + confidence, "Why ·" reasoning, re-bucket chips, original source (if any), the editable proposed draft, the comment field, and the outcome actions — `Approve` · `Comment` · `Snooze` · `Schedule` · `I'll do it` · `Reject` (for `fyi` recs: `Keep` · `Dismiss`). The old `Review` button is gone — it only toggled the inline drawer, which no longer exists.
- **Auto-open source:** on selection, if the setting is on **and** `SourceLink(from: rec) != nil`, call `sourcePanel.open(link)`. Otherwise leave the source panel untouched.
- **Selection churn:** when the selected rec leaves the pending queue (approved / scheduled / snoozed / rejected), selection moves to the next pending rec, or clears if none remain.
- **Empty state:** when there are no pending recs (or none selected), the detail pane shows a calm "Nothing selected" placeholder.
- **Setting toggle:** a small control in the Agent header (e.g. a labelled toggle / icon button), persisted via `@AppStorage`. The source-panel glyph and ⌘⇧S continue to work regardless of the setting.

## Architecture

Follows the project rule (pure decisions in `Logic/`, render/dispatch in `Views/`) and improves `AgentConsoleView` (currently 549 lines) by extracting the detail.

- **`Views/RecommendationDetailView.swift`** (new) — the triage workspace for one recommendation: the drawer content (re-bucket, original source, draft editor, comment) + the outcome action row, extracted verbatim from today's `RecommendationRow`. One clear responsibility; reused by the master-detail right pane. Removing the inline drawer from `RecommendationRow` slims that type to a compact, selectable summary.
- **`Views/RecommendationRow.swift`** (extracted from `AgentConsoleView.swift`, or kept in place) — becomes a compact, selectable summary: provenance pill, sparkles + title + "Always needs you" lock + source glyph + confidence meter. No `expanded` state, no drawer, no `Review` button. Exposes selection (highlights when selected).
- **`Views/AgentConsoleView.swift`** (modify) — the `RECOMMENDATIONS` queue becomes a `list │ detail` split: the left column is the existing console scroll (header, source/sweep/trust row, source settings, the recommendation rows, and the `REVIEW` output-card section unchanged) with compact rec rows; the right column is `RecommendationDetailView` for the selected rec (or the empty placeholder). Adds `@State` selection and reads `@Environment(SourcePanelController.self)` to drive auto-open.
- **`Logic/RecommendationSelection.swift`** (new, small, pure, tested) — the testable decisions, kept out of the view: `nextSelection(after:in:)` (which rec to select when the current one leaves the queue / on arrival) and `shouldAutoOpenSource(settingOn:rec:)` (`settingOn && SourceLink(from: rec) != nil`). Keeps `AgentConsoleView` dumb.
- **Setting:** `@AppStorage("autoOpenSourceOnSelect")` (default `true`) — a local UI preference; no SwiftData/CloudKit involvement.

The source `.inspector` stays attached at `RootView` (from #20). `AgentConsoleView`'s internal `list │ detail` split nests inside the content column, and the inspector composes on the trailing edge — yielding the 3-/4-column Model B layout.

## Testing

This is largely a view/layout change → **build + eye** (Leon confirms the live look; the in-session shell can't screenshot). The extracted pure decisions are unit-tested:

- **`Tests/MustardTests/RecommendationSelectionTests.swift`** (new):
  - `shouldAutoOpenSource` — on + rec-with-http-source → true; on + sourceless rec → false; off + sourced rec → false.
  - `nextSelection` — after the selected rec leaves a list, returns the next pending; returns the first on arrival; returns nil when the queue is empty.
- `swift test` (whole suite) and `swift build` must pass.

## Out of scope (YAGNI)

- The `REVIEW` queue (output cards) keeps its current inline accept/revise/discard — no master-detail there.
- Other screens (Today / Board / Week / Lists) and the (non-existent) Inbox.
- Keeping inline-expand as an alternative mode — it's removed, not toggled.
- Multi-select / keyboard arrow navigation of the list (could come later; not now).
