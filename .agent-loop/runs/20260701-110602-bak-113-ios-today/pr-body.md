## BAK-113 — iOS Today + shared task-detail sheet

Mobile Today: day-progress bar, agent nudge (→ Triage), timeline rows (check-circle toggle, agent tag, area dot, mobile-only gate pills Approve/Review/Blocked), inbox — reusing tested DayPlanner/AgentInbox. Tapping a row opens `MobileTaskSheet`, the shared read-oriented task-detail bottom sheet (the task half of BAK-115) with a compact stage-adaptive footer reusing PersonalBoard/TaskCompletion.

iOS `build-ios.sh` → BUILD SUCCEEDED · macOS untouched. Risk: medium (iOS UI).
