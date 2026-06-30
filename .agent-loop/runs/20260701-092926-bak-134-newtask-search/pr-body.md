## BAK-134 — Board "+ New task" + Search

Adds the two missing Board header affordances from the prototype.
- **+ New task** → inserts an inbox task (owner from the current lens) and opens it in the detail/edit sheet.
- **Search** → case-insensitive title filter per column via pure `PersonalBoard.filterBySearch` (TDD).

swift build clean · swift test 419 pass/1 skip (+2). Risk: medium.
