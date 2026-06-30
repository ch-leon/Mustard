## BAK-135 — Board drag-over column highlight

Each board column now shows a 2px accent outline while a card is dragged over it (via `.dropDestination(isTargeted:)` + a `dropTargetStage` @State). Matches the prototype `bcol-drop`.

swift build clean · swift test 417 pass/1 skip. Risk: low (view-only).
