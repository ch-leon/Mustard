# Parity audit — Task detail + create/edit form (BAK-118)

Shipped `TaskDetailSheet.swift` (Mustard merges detail + create/edit into ONE editor
sheet) vs the prototype's detail slide-over + create/edit form. Audited 2026-07-01
(post BAK-100 reverse transitions + BAK-107 blockedByTask).

## Create/edit form — strong parity
Title, description (edit/preview), Stage, Priority, Assignee, Due, Scheduled, Estimate,
Parent (ParentPicker), **Recurrence** (present — BAK-51 caveat resolved), **Tags** (chip
input), **Blocked-by** (BlockedByPicker — BAK-107), Area, Subtasks (add + progress).
Bonus: Links (BAK-91) + agent Action picker.

## Fixed inline (this issue)
- **Interactive subtasks:** checkbox is now a toggle Button (done ↔ planned) + a remove
  (✕) control (was display-only).
- **Assignee accent** tints purple when owner == agent (blue↔purple cue).

## Larger gaps → follow-ups
- **BAK-136** — stage-adaptive footer matrix (forward gate actions on the detail panel:
  Approve & run / Accept output / Take back / Move to review / proposed Approve/Schedule/
  Dismiss). BAK-100 landed the reverse halves + board-side inline actions.
- **BAK-137** — read-mode approval view (stage badge, 🔒 notice, confidence bars, WHY,
  draft blocks) — the sheet is currently edit-only.

## Non-gaps (don't chase)
- Green agent-output block — N-A (not in the prototype detail either; review is
  console/board-side per ADR-0010).
- "Create disabled until title" — N-A (merged sheet binds a live model; no separate
  create gate).
