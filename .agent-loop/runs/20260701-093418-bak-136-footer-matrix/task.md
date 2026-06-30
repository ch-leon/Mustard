# BAK-136 — Task detail stage-adaptive footer matrix

**Run:** 20260701-093418 · **Milestone:** Redesign · Desktop delta · **Risk:** medium (TaskDetailSheet)

Replaced the flat footer with the handoff's six-branch matrix (Delete stays leading):
- needsApproval → Approve & run/Approve · I'll do it · Deny
- needsReview → Accept output · Request changes · Discard
- queued → Move to review · Hold
- forAgent → Take back
- proposed inbox → Approve · Schedule · I'll do it · Dismiss
- your tasks → Mark done · Hand to ✦ agent
Forward gate actions reuse `PersonalBoard.approveTarget`/`move`; no forked state machine.
