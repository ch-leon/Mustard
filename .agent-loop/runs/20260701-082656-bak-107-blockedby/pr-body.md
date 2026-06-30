## BAK-107 — Task-to-task dependency (blockedByTask)

Adds a real "Blocked by" task relation (was free-text only).

### Changes
- `MustardTask.blockedByTask: MustardTask?` — optional `@Relationship(.nullify)`, CloudKit-safe; additive optional so existing stores decode with nil (no migration).
- `isBlocked` now true when the blocker is set + not done (free-text reason still honoured); one level deep (no recursion on mutual deps).
- `BlockedByPicker` + a "Blocked by" row in the detail/create-edit form (search by title; excludes self + done).
- `BlockedByTests` (4).

### Checks
swift build clean · swift test 417 pass / 1 skip / 0 failures (+4).

### Risk
Medium — additive schema relationship + 2 views; no high paths; no outward actions.
