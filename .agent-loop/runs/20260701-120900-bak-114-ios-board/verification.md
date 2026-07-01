# BAK-114 — iOS Board (stacked sections + gate buttons)
Run: 20260701-120900 · Milestone: Redesign · iOS companion · Risk: medium (iOS UI; macOS untouched)
- MobileBoardView: vertical stacked sections (one per non-empty stage in owner order), owner chips (Everyone/Mine/Agent) + area chips (All/<areas>/Personal) via shared MobileFilters, "● N waiting" toolbar pill. Empty stages omitted (no collapse strips). Reuses PersonalBoard.columns/tasks/waitingCount.
- MobileBoardCard: priority flag, ✦ Agent label (no owner toggle), ✦ Proposed, 🔒, title, area meta, left agent accent, inline gate buttons (✓ Approve & run / ✓ Accept + Deny/Discard via approveTarget/move + delete). Tap → MobileTaskSheet. No drag.

## Review round 1 — CHANGES-REQUESTED → fixed
Blocking: (B1) working tree didn't build; (B2) nested Button-in-Button double-fire on the card.
Fix (same change): MobileBoardCard is no longer a Button — `cardBody` + `.contentShape` +
`.onTapGesture { onOpen }`; gate Buttons stay children (take hit-test priority, so a gate
tap doesn't also open the sheet). Matches desktop BoardView `.onTapGesture` pattern.
`./build-ios.sh` → BUILD SUCCEEDED.
