# BAK-113 — iOS Today + shared task-detail sheet

**Run:** 20260701-110602 · **Milestone:** Redesign · iOS companion · **Risk:** medium (iOS UI; macOS untouched)

- `MobileTodayView`: day-progress bar, agent nudge (→ Triage tab), timeline rows with
  check-circle toggle + agent tag + area dot + **mobile-only gate pills** (Approve/Review/
  Blocked), and the INBOX section. Reuses DayPlanner + AgentInbox (tested).
- `MobileTaskSheet` (the task half of BAK-115): read-oriented detail bottom sheet (stage
  badge, gated notice, confidence, WHY/draft, DETAILS incl. Day + Blocked-by, tags,
  interactive subtasks) + compact stage-adaptive footer reusing PersonalBoard.approveTarget/
  move + TaskCompletion. Tapping a Today row opens it.
- Wired into the shell (Today tab).

## Note
The triage-detail sheet half of BAK-115 lands with BAK-119. macOS/SPM untouched.
