# Verification — BAK-101
- **swift build** → Build complete (3.71s) ✅
- **swift test** → 388 pass / 1 skip / 0 failures ✅ (+1 BoardFocusTests)
- **lint** → no-op ✅

## Acceptance
- [x] Waiting pill toggles review-focus; collapses to needsApproval + needsReview.
- [x] Pill flips to "Exit review queue" (filled) when focused; visible at count 0 while focused.
- [x] Caption reflects the focus view.
- [x] Count is derived (PersonalBoard.waitingCount), never stored.

## Notes
Leon to eyeball: the focus toggle collapse/restore and the filled pill state.
