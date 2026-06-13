# Mustard — Rich Task Properties Design

> Written 2026-06-13. Feature spec; sibling to [`foundation-design.md`](foundation-design.md).
> Ports the proven task model + automation from the sibling **Triage-tool** (Mustard's
> web predecessor) into Mustard's SwiftData model and `TaskDetailSheet`.

## Goal

Bring Mustard's task detail editor to parity with the Triage-tool's `TaskDrawer`
(the design reference / screenshot): the full property set **with the behavioural
automation behind it**, in Mustard's "Things-3-calm" styling.

Today `MustardTask` carries `title`, `notes`, `status`, `owner` (assignee),
`scheduledAt`, `estimateMinutes`, `list`. This feature adds **priority, due date,
recurrence, tags, blocked-by reason, and a parent/subtask hierarchy** — plus
recurrence spawning, subtask cascade-completion, blocked-aware planning, and a
parent cycle guard.

> The dead "+" quick-capture buttons (Today / Board / Notch were decorative
> `Image`s, not `Button`s) are a **separate bugfix**, already shipped — not part of
> this spec.

## Decisions (resolved with Leon)

- **Status enum unchanged.** Keep Mustard's `inbox / planned / inProgress / done /
  someday` (wired into `DayPlanner`, `PersonalBoard`, `WeekPlanner`, `NotchTicker`).
  "Blocked" is a **derived flag** (`isBlocked = !blockedReason.isEmpty`), *not* a
  status — avoids re-architecting the planner/board logic and their tests.
- **Full set + automation** (not store-only): recurrence spawns the next instance,
  parent completion cascades to children, blocked tasks drop out of "next-up".
- **Reference = Triage-tool**: `server/recurrence.ts`, `server/vault.ts`
  (`applyStatusTransition`), `server/cycleGuard.ts`, `server/schema.ts`. Mustard
  mirrors their semantics so the two apps stay consistent.
- **Subtask delete rule = `.nullify`** (deleting a parent promotes children to
  top-level; it does not delete them).
- **Estimate retained** (`estimateMinutes`, already present) and surfaced in the
  sheet, though the screenshot omits it (Leon's explicit addition).

## Data model (`Models/`)

New enums in `Enums.swift`:

- `TaskPriority: high, normal, low` — default `.normal`; `sortRank` (high = 0 …
  low = 2) for ordering within a status. `Codable, CaseIterable, Identifiable`.
- `Recurrence: daily, weekdays, weekly, monthly` — `Codable, CaseIterable,
  Identifiable`; optional on the task (`nil` = "none").

New stored properties on `MustardTask` (all defaulted / optional → **lightweight
migration**):

| Property | Type | Default |
|---|---|---|
| `priorityRaw` | `String` | `TaskPriority.normal.rawValue` |
| `dueAt` | `Date?` | `nil` |
| `recurrenceRaw` | `String?` | `nil` |
| `tags` | `[String]` | `[]` |
| `blockedReason` | `String` | `""` |
| `parent` | `MustardTask?` | `nil` |
| `subtasks` | `[MustardTask]?` — inverse of `parent`, deleteRule `.nullify` | `[]` |
| `recurredFrom` | `String?` (uid of the spawning instance) | `nil` |
| `autoCompleted` | `Bool` | `false` |

Computed: `priority`, `recurrence` (raw ↔ enum), `isBlocked`,
`subtaskProgress: (done: Int, total: Int)`.

## Logic units (TDD, pinned UTC — per CLAUDE.md)

Pure, decision-bearing code lands in `Logic/`, failing test first:

1. **`Recurrence.nextDate(after:calendar:)`** — `daily` +1d, `weekly` +7d,
   `weekdays` → next Mon–Fri, `monthly` +1mo **clamped to the last valid day**
   (Jan 31 → Feb 28/29). Mirrors `recurrence.ts`. Tests: each rule; month-end
   clamp; Fri/Sat/Sun → Mon.
2. **`RecurrenceEngine.nextInstance(of:now:) -> MustardTask?`** — `nil` when
   `recurrence == nil`; else a new **un-inserted** task: title / notes / priority /
   tags / parent / recurrence copied, `dueAt` advanced from `dueAt ?? now`, status
   reset (`.planned` if dated else `.inbox`), `completedAt = nil`,
   `recurredFrom = original.uid`. Pure → testable.
3. **`TaskHierarchy.wouldCreateCycle(_ tasks:taskId:newParentId:) -> Bool`** —
   mirrors `cycleGuard.ts`. Tests: self-parent, ancestor chain, pre-existing cycle.
4. **`MustardTask.markDone(now:)`** — already stamps `done`/`completedAt`; extend to
   cascade: open subtasks (`status.isOpen`) → `done` + `autoCompleted = true`.
   Completing all children does **not** auto-complete the parent (one direction
   only, matching the reference). Tested via in-memory container in `ModelTests`.
5. **Blocked enforcement** — `DayPlanner` (unscheduled + carry-forward) and
   `NotchTicker` (focus / next-up) exclude `isBlocked` tasks (they stay visible in
   lists, just aren't *suggested*). Added to the existing planner suites.
6. **`TaskPriority.sortRank`** — ordering within a status (high first). Tested.

**Completion choke-point** (orchestration; build + eye, not unit-tested):
`TaskCompletion.complete(_ task:in context:now:)` → `nextInstance` → `markDone`
(cascade) → inserts the spawned task. **Every** "done" path routes through it
(`TodayView` toggle, `TaskDetailSheet` "Mark done", Board drag-to-Done). Un-completing
is a plain status change that clears `completedAt`.

## UI (`Views/`; build + Leon's eye)

Rebuild `TaskDetailSheet` to the screenshot's three sections, in `Theme` styling:

- **Properties** (new `PropertyRow` label/control layout): Status · Priority ·
  Assignee (me/agent segmented) · Due (date) · Scheduled (date+time) · Estimate ·
  Parent (`ParentPicker`, cycle-guarded) · Recurrence · Tags (`TagChipInput`) ·
  Blocked by (text) · **In** (`TaskList` picker — pick an existing list or none;
  new, the list is currently never shown in the sheet).
- **Subtasks (done/total)**: child rows (tap → open that task's sheet); "Add subtask"
  creates a child with `parent` set.
- **Body**: edit / preview segmented — edit = `TextEditor($task.notes)`, preview =
  `Text(AttributedString(markdown:))`.

New Views: `PropertyRow`, `TagChipInput`, `ParentPicker` (subtask rows inline). The
Board card gains a **blocked badge**; other screens are otherwise unchanged.

## Migration & risk

Additive optional/defaulted fields + one optional self-referential relationship →
SwiftData **lightweight automatic migration**; the on-disk store opens without a
reset. `MustardContainer.make()` still `fatalError`s on an unexpected
non-lightweight mismatch — if that ever fires in dev, delete
`~/Library/Application Support/Mustard/mustard.store`.

## Out of scope (YAGNI)

- Interactive checkboxes *inside* the markdown body — real subtasks cover checkable
  items.
- A separate `Tag` model / tag-management UI — plain `[String]`, add/remove chips only.
- An `origin` (triage/manual) field — `Recommendation` already carries agent provenance.
- Changing the status vocabulary / a dedicated `blocked` column — explicitly decided
  against.
- Recurrence beyond the four rules; custom RRULE / end-dates.

## Build sequence (→ implementation plan)

1. Enums + model fields + computed props; confirm migration (build & run).
2. `Recurrence.nextDate` (TDD).
3. `RecurrenceEngine.nextInstance` + `TaskHierarchy` (cycle + progress) (TDD).
4. `markDone` cascade + blocked enforcement in `DayPlanner` / `NotchTicker` (TDD).
5. `TaskCompletion` choke-point; route all done-paths through it (build + eye).
6. `TaskDetailSheet` rebuild + `PropertyRow` / `TagChipInput` / `ParentPicker`;
   Board blocked badge (build + eye).

Backlog: this supersedes **"Recurrence for tasks"** under *Later* in
[`build-order.md`](build-order.md).
