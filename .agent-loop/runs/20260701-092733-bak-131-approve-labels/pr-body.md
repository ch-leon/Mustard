## BAK-131 — Contextual approve label

Rename the recommendation-detail primary "Approve" → "Approve & run" (the prototype's primary label; accurate since approving executes). The prototype's "Approve & schedule" variant is the existing separate Schedule button. Same `decide(.approved)` dispatch.

swift build clean · swift test 417 pass/1 skip. Risk: low (view-only label).
