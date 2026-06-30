# Verification — BAK-107
- **swift build** → Build complete (4.03s) ✅
- **swift test** → 417 pass / 1 skip / 0 failures ✅ (+4 BlockedByTests)
- **lint** → no-op ✅

## Acceptance
- [x] blockedByTask relation added (optional, nullify, CloudKit-safe).
- [x] isBlocked derives from an unfinished blocker; free-text still works.
- [x] Detail/form "Blocked by" picker (search; link/unlink); excludes self + done.
- [x] Additive optional → existing data decodes (no migration).

## Notes
Leon to eyeball the Blocked-by picker in the detail sheet + that a blocked-by task shows the blocked treatment on the board.
