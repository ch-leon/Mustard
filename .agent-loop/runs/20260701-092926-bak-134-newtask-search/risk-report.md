# Risk Report — BAK-134
**MEDIUM** → auto-merge after fresh-context review.
- Label: Feature. Paths: BoardView.swift (view) + PersonalBoard.swift (pure filter helper) + BoardFocusTests. → Sources/ = medium.
- No high paths. makeNewTask inserts a task (consistent with QuickColumnAdd's insert-then-edit). No schema/outward.
