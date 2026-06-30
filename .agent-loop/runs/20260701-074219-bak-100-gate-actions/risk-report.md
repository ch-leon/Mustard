# Risk Report — BAK-100
**MEDIUM** → auto-merge after fresh-context review.
- Label: Feature. Paths: PersonalBoard.swift (Logic), MustardBoardCard.swift + TaskDetailSheet.swift (Views), GateTransitionTests. → Sources/ = medium.
- No high paths (TrustPolicy/RecommendationAction/auth/ClaudeRunner untouched). Note: gate semantics here are board-task stage moves, not the recommendation gating in RecommendationAction.
- Behaviour: Deny/Discard delete a task (intended per handoff). No schema change. No outward actions.
