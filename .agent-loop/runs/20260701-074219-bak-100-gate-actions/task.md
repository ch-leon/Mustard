# BAK-100 — Board inline gate actions + detail reverse transitions

**Run:** 20260701-074219-bak-100-gate-actions · **Milestone:** Redesign · Desktop delta
**Risk class:** medium (Sources/ — Logic helper + 2 views)

## Done
- **Logic (TDD):** `PersonalBoard.approveTarget(for:)` — needsApproval → queued (gated)
  / needsReview (non-gated); needsReview → done; nil off-gate. `GateTransitionTests` 5/5.
- **MustardBoardCard:** hover-revealed inline gate actions on needsApproval/needsReview —
  primary "✓ Approve & run" (gated) / "✓ Approve" (non-gated) / "✓ Accept" (review);
  secondary "Deny"/"Discard" (deletes). Buttons reuse `PersonalBoard.approveTarget`/`move`
  and `context.delete`; `.buttonStyle(.plain)` so they consume the tap (don't open detail).
- **TaskDetailSheet:** reverse transitions — "Hold" (queued→needsApproval) and
  "Request changes" (needsReview→queued) via `PersonalBoard.move`.

## Out of scope
The full stage-adaptive footer matrix is BAK-118. Executing a queued task (the runner)
is the deferred Phase-3 worker — "Approve & run" stages to queued, as today.
