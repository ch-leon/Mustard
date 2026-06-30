# BAK-101 — Board review-focus mode + view caption

**Run:** 20260701-074835-bak-101-review-focus · **Milestone:** Redesign · Desktop delta
**Risk class:** medium (Sources/ — BoardView + PersonalBoard constant)

## Done
- The header "● N waiting on you" pill is now a **button** that toggles review-focus.
  When focused: columns collapse to the two gate stages, the pill flips to **"Exit
  review queue"** (filled purple), and the caption becomes "Review queue — everything
  waiting on you, both gates." The pill stays visible while focused even if the count
  hits 0 (so you can exit).
- `PersonalBoard.gateStages = [.needsApproval, .needsReview]` (reused by the columns).
- Migrated the pill's inline hex to Theme tokens (agentText/agentTintLight).

## Notes
Waiting count + base caption already existed (BAK-79); this adds the toggle behaviour.
`BoardFocusTests` guards the focus column set.
