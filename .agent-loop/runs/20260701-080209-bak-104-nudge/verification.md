# Verification — BAK-104
- **swift build** → Build complete (3.25s) ✅
- **swift test** → 398 pass / 1 skip / 0 failures ✅ (+3 AgentInboxTests)
- **lint** → no-op ✅

## Acceptance
- [x] Nudge appears only when count > 0; auto-hides at 0; ✕ dismisses.
- [x] Tap → Agent console (onPlan).
- [x] Count derived (recs + needsReview), snooze/ignore respected.
- [x] Shared helper reused by RootView badge.

## Notes
Leon to eyeball the nudge card + dismiss + tap-to-console.
