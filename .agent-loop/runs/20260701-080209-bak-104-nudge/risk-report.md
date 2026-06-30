# Risk Report — BAK-104
**MEDIUM** → auto-merge after fresh-context review.
- Label: Feature. Paths: AgentInbox.swift (Logic), TodayView.swift + RootView.swift (Views), AgentInboxTests. → Sources/ = medium.
- No high paths. No schema change. No outward actions.
- Side effect: RootView badge now respects snooze/ignore (intended improvement; count can only shrink or stay equal vs before).
