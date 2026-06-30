# Risk Report — BAK-99

**Risk class: MEDIUM** → auto-merge after fresh-context review.

- **Label:** Feature.
- **Touched paths:** `Sources/MustardKit/Models/{Enums,MustardTask}.swift`,
  `Sources/MustardKit/Views/MustardBoardCard.swift`, `Tests/MustardTests/BoardCardMetaTests.swift`.
  → `Sources/` = medium.
- **No high-risk paths** (TrustPolicy/RecommendationAction/auth/ClaudeRunner untouched).
- **Schema:** additive only — new enum case (stable rawValues), new computed property.
  No stored-property change → no SwiftData migration.
- **Outward actions:** none.

Medium → auto-merges on a clean fresh-context review. No deep-review panel.
