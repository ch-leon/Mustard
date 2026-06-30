## BAK-136 — Task detail stage-adaptive footer matrix

Replace the flat detail footer with the handoff's six-branch matrix (needsApproval / needsReview / queued / forAgent / proposed-inbox / your-tasks). Delete stays leading. Forward gate actions reuse `PersonalBoard.approveTarget`/`move` (no forked state machine); terminal actions dismiss, transitions keep the sheet open.

swift build clean · swift test 419 pass/1 skip. Risk: medium (view).
