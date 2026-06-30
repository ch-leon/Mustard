# Risk Report — BAK-109
**MEDIUM** → auto-merge after fresh-context review.
- Label: Feature. Paths: WeekPlanner.swift (Logic), WeekView.swift (View), WeekBalanceTests. → Sources/ = medium.
- No high paths. No schema change. No outward actions. Balance mutates task.scheduledAt in-place but is fully reversible via the Undo snapshot.
