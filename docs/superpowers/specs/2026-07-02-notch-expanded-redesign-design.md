# Notch — Expanded View Redesign & External-Monitor Targeting (Design)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

## Context

The notch surface (`Sources/MustardKit/Views/NotchSurface.swift`, spec §6a,
plan `docs/plans/2026-06-13-mustard-notch.md`) currently expands on hover into
a panel showing: the focus task, up to 3 today's meetings, up to 3 pending
recommendations with inline Approve/Deny, and a quick-capture field.

Two problems prompted this redesign:

1. **Wrong content shape.** The current panel doesn't give a real sense of the
   day — it shows meetings and recs separately, with no task list, no
   progress signal, and no way to jump into a task's detail. Leon wants
   something closer to a mini Today view: a triage summary card plus a full
   chronological agenda (tasks + meetings) with a done/total progress bar.
2. **Wrong screen when an external monitor is connected.** `NotchController`
   always picks the screen with `safeAreaInsets.top > 0` (the built-in notch)
   if one exists, so with an external monitor plugged in the notch stays
   stuck on the closed/background laptop screen instead of the display Leon
   is actually looking at.

## Goals

- Replace the hover-expanded panel's content with: an `Agent` header, a
  triage summary card (count + deep link to the Agent console), and a full
  today agenda (tasks + meetings merged, chronological, with a progress bar).
- Make rows interactive: tap a row to open its detail, tap the status circle
  to toggle a task done, tap Join to open a meeting link.
- Fix screen selection to prefer an external monitor over the built-in
  notch display when one is connected.

## Non-goals

- No live trust-level badge in the notch header (deferred — plain "Agent"
  label only).
- No inline Approve/Deny for recommendations in the notch — triage moves
  entirely to the Agent console via the summary card's "Open" link.
- No user-facing setting to pick a specific display by name — screen
  selection is automatic (external-preferred), not configurable.
- No changes to the idle (collapsed) strip — `NotchTicker` and the idle
  content are unchanged.

## Design

### 1. Screen targeting

`NotchController.screen` (`NotchSurface.swift:22-24`) is replaced with a pure,
testable selection function operating on lightweight descriptors so the
policy can be unit tested without live `NSScreen`:

```swift
struct ScreenDescriptor: Equatable {
    let id: AnyHashable
    let hasNotch: Bool
    let isMain: Bool
}

enum NotchScreenPicker {
    /// Prefer a non-notch (external) screen when more than one display is
    /// connected; otherwise fall back to the notch screen, then `.main`.
    static func choose(from screens: [ScreenDescriptor]) -> ScreenDescriptor?
}
```

Rules, in order:
1. If there's more than one screen and at least one has `hasNotch == false`,
   pick the first non-notch screen.
2. Else if a notch screen exists, pick it (today's behavior, laptop-only).
3. Else pick the screen marked `isMain`.
4. Else `nil` (no screens — caller already guards this).

`NotchController` builds `[ScreenDescriptor]` from `NSScreen.screens` and
calls `NotchScreenPicker.choose`, then resolves back to the matching
`NSScreen` by `id`. Applies to both `idleFrame`/`expandedFrame` — the whole
panel (idle strip and expanded state) lives on whichever screen is chosen,
consistent with today's single-panel model (no multi-panel mirroring).

### 2. Expanded content

Replaces `NotchView.expandedContent` (`NotchSurface.swift:205-327`) entirely.
Layout, top to bottom:

1. **Header row:** `"Agent"` label, plain text, no badge.
2. **Triage summary card:** sparkle icon + `"\(total) items to triage"` with
   a subline `"\(approvals) approval(s) · \(reviews) review(s) waiting"`
   (omit a clause if its count is 0; card is hidden entirely if `total == 0`).
   `approvals` = `pending.count` (existing `RecommendationQueue.pending`
   computed property, unchanged). `reviews` = `needsReviewCount` (existing
   computed property, unchanged). Trailing `"Open ↗"` control activates the
   main window and switches it to the Agent console tab.
3. **Today agenda:**
   - Header row: `"TODAY · <day short label>"` left, `"\(done) of \(total)
     done"` right, `done`/`total` from `DayPlanner.dayProgress(tasks, day:
     .now)` (existing function, tasks only — events have no done state).
   - Thin progress bar (teal fill, existing notch palette).
   - Rows from the new `DayPlanner.agenda(tasks:events:day:)` (see §3),
     wrapped in a `ScrollView` capped at a fixed max height so a long day
     scrolls internally instead of growing the panel.
   - Row anatomy: time label (or `"Any"` for untimed tasks) · status circle ·
     title (strikethrough + dimmed when done) · tag chip (task's
     `list?.area` color + name, when present) · `"Join"` button (when the
     item is an event with a non-nil `joinURL`).
   - **Status circle tap:** toggles the task's stage between its open state
     and `.done` in place (no-op for events — they have no done state, so
     their circle renders as a static outline with no tap target).
   - **Row tap (elsewhere in the row):** sets a selection on `NotchNavigation`
     (see §4) so the main window opens the task/event detail.
4. **Quick capture:** existing `capture()` logic, restyled as a text field
   with a trailing `"Add"` button (replacing the current leading `+` icon
   button) to match the mockup.

### 3. New pure logic — `DayPlanner.agenda`

```swift
public struct AgendaItem: Identifiable {
    public enum Kind { case task(MustardTask), event(CalendarEvent) }
    public let id: PersistentIdentifier
    public let kind: Kind
    public let time: Date?        // nil for untimed tasks
    public let title: String
    public let isDone: Bool       // events always false
    public let tagLabel: String?  // task.list?.area?.name
    public let tagColor: Color?   // task.list?.area?.color
    public let joinURL: String?   // events only
}

extension DayPlanner {
    /// Merges today's tasks and events into one chronological list.
    /// Timed items sort by time; untimed tasks sort last, in existing
    /// task order. Only tasks from `tasksForDay` are included (existing
    /// open/blocked filtering unchanged); events are today's events
    /// unfiltered by status (no done state to filter on).
    public static func agenda(
        tasks: [MustardTask], events: [CalendarEvent], day: Date,
        calendar: Calendar = .current
    ) -> [AgendaItem]
}
```

TDD'd in `DayPlannerTests` with the existing pinned UTC calendar/fixture
pattern: mixed timed tasks, an untimed task, and an event on the same day;
assert ordering (timed ascending, untimed last) and field mapping.

### 4. Cross-window navigation — `NotchNavigation`

A small `@Observable` object, environment-injected the same way `AgentService`
already is, so `NotchView` (running in its own `NSPanel`) can request the main
window open a detail without `NotchController` reaching into `RootView`'s
internal screen-selection state directly:

```swift
@Observable
public final class NotchNavigation {
    public var pendingTaskID: PersistentIdentifier?
    public var pendingEventID: PersistentIdentifier?
    public var openAgentConsole: Bool = false
}
```

`NotchView` sets the relevant field on row tap / "Open ↗" tap.
`RootView` observes the same instance (already shares environment across
windows via `MustardContainer`/`MustardApp`), and on a non-nil change:
activates the app + main window (`NSApp.activate`, existing pattern reused
from other window-toggle code), switches `screen` to the right tab, and
(for tasks) sets its existing `selectedTask` state to present
`TaskDetailSheet` — reusing the sheet pattern already used by
`TodayView`/`BoardView`. After consuming, `RootView` resets the field to
`nil` so re-tapping the same row re-triggers it.

## Testing

- `NotchScreenPicker.choose` — pure, TDD'd: external+notch connected →
  external; notch-only → notch; neither → main; empty → nil.
- `DayPlanner.agenda` — pure, TDD'd: ordering, untimed-last, tag/joinURL
  mapping, done state from task stage only.
- `NotchView` layout, row tap wiring, and `NotchNavigation` plumbing are
  verified by build + eyes per project convention (views aren't unit tested).

## Open questions / risks

None outstanding — all resolved during brainstorming (trust badge deferred,
inline triage dropped, screen policy is external-preferred with no manual
override for now).
