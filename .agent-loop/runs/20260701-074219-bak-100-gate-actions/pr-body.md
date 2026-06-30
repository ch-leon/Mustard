## BAK-100 — Board inline gate actions + detail reverse transitions

Puts the two gates directly on the board so a recommendation can be triaged without opening the console.

### Changes
- **Logic (TDD):** `PersonalBoard.approveTarget(for:)` — needsApproval → queued (gated) / needsReview (non-gated); needsReview → done.
- **MustardBoardCard:** hover-revealed inline actions on the two gate stages — primary "✓ Approve & run"/"✓ Approve"/"✓ Accept" + secondary "Deny"/"Discard" (deletes). Reuses `approveTarget`/`move`/`context.delete`.
- **TaskDetailSheet:** "Hold" (queued→needsApproval) and "Request changes" (needsReview→queued).
- **Tests:** `GateTransitionTests` (5).

### Checks
swift build clean · swift test 387 pass / 1 skip / 0 failures (+5).

### Risk
Medium — board-task stage transitions in Logic + 2 views; no auth/trust/ClaudeRunner; no schema change.
