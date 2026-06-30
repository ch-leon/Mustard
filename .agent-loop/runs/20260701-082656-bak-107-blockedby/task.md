# BAK-107 — Task-to-task dependency: blockedByTask

**Run:** 20260701-082656-bak-107-blockedby · **Milestone:** Redesign · Desktop delta
**Risk class:** medium (Sources/ — additive SwiftData relationship + detail/form)

## Done
- `MustardTask.blockedByTask: MustardTask?` — `@Relationship(deleteRule: .nullify)`,
  optional, no inverse → CloudKit-safe (ADR-0001). Additive optional → existing stores
  decode with nil (SwiftData lightweight; no migration).
- `isBlocked` now true when `blockedByTask` is set and not done (keeps the free-text
  `blockedReason` path). Looks one level deep, so a mutual A↔B dependency can't recurse.
- `BlockedByPicker` (mirrors `ParentPicker`): search by title, excludes self + done;
  added a "Blocked by" row to the detail/create-edit form (DETAILS list).

## Notes
`BlockedByTests` cover open/done blocker + free-text + none. The board card already
renders the blocked accent + row from `isBlocked`, so a blocked-by task shows as blocked.
