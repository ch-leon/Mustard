## BAK-101 — Board review-focus mode + caption

The header "● N waiting on you" pill now toggles a review-focus mode: the board collapses to the two gate columns (needsApproval + needsReview), the pill flips to "Exit review queue" (filled purple), and the caption updates. Pill stays visible while focused even at count 0.

### Changes
- `BoardView`: waiting pill → toggle button; columns use `PersonalBoard.gateStages` when focused; focus-aware caption; pill hex → Theme tokens.
- `PersonalBoard.gateStages` constant.
- `BoardFocusTests` guards the focus column set.

### Checks
swift build clean · swift test 388 pass / 1 skip / 0 failures (+1).

### Risk
Medium — view-state toggle + a Logic constant; no schema/outward.
