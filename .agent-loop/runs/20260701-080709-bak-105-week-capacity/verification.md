# Verification — BAK-105
- **swift build** → Build complete (3.87s) ✅
- **swift test** → 403 pass / 1 skip / 0 failures ✅ (+5 WeekCapacityTests)
- **lint** → no-op ✅

## Acceptance
- [x] Capacity + tier computed correctly across boundaries (360/480) — tested.
- [x] capacityLabel formats —/m/h correctly — tested.
- [x] Tasks bucket into the right time-of-day section (untimed → Anytime) — tested.
- [x] Day header shows capacity label + load bar; non-axis tasks grouped.

## Notes
Pinned UTC + ISO fixtures (CLAUDE.md). Leon to eyeball the load bar colours + section headers.
