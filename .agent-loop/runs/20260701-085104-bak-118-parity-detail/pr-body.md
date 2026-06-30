## BAK-118 — Parity audit: detail + create/edit form

Audited the merged TaskDetailSheet vs the prototype (docs/design/redesign-2026/parity/detail-form.md). Create/edit form is strong parity (recurrence, tags, blocked-by, area all present).

### Inline fixes
- Subtasks are now interactive: checkbox toggles done, + a remove (✕) control (was display-only).
- Assignee segmented control tints purple when owner == agent.

### Follow-ups
- BAK-136 (stage-adaptive footer matrix — forward gate actions on the detail panel).
- BAK-137 (read-mode approval view — stage badge, WHY, draft, confidence).

### Checks
swift build clean · swift test 417 pass / 1 skip / 0 failures.

### Risk
Medium — view edits + docs; no schema/outward.
