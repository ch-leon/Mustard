# Verification — BAK-99

## Required checks
- **swift build** → `Build complete! (3.75s)` ✅
- **swift test** → `382 tests, 1 skipped, 0 failures` ✅ (+5 BoardCardMetaTests)
- **lint** → no-op per checks.yml ✅ n/a

## Acceptance
- [x] Priority flag pill (HIGH / URGENT) in the card top row.
- [x] "✦ Proposed" pill for agent-proposed inbox tasks.
- [x] Tags row (#tag, max 3) below the meta row.
- [x] Existing card elements (owner toggle / padlock / confidence / status / blocked) unchanged.

## Notes
- `TaskPriority` reorder changes only `allCases` iteration order (rawValues stable →
  no data migration); the create/edit Priority picker now offers Urgent automatically.
- View rendering verified by build + the SnapshotRenderTests; Leon to eyeball the new
  flag/pill/tags on the board once.
