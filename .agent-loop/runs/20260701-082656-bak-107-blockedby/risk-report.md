# Risk Report — BAK-107
**MEDIUM** → auto-merge after fresh-context review.
- Label: Feature. Paths: MustardTask.swift (Model — schema), TaskDetailSheet.swift + BlockedByPicker.swift (Views), BlockedByTests. → Sources/ = medium.
- **Schema change:** additive optional relationship (`blockedByTask`) — SwiftData lightweight, existing stores decode with nil. No high-risk paths (no TrustPolicy/RecommendationAction/auth/ClaudeRunner).
- No outward actions.
