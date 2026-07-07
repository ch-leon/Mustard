(Snapshot of PR #78 body as finalized — canonical copy lives on GitHub.)

Title: feat(craft): Theme depth/motion tokens, surface polish + live Craft Notes editor

Spec gate + full implementation of the Craft-inspired pass: Phase 0 Theme
foundation (Elevation/Motion/Metrics + editorial type, NS bridges), Phase 1
surface polish (MarkdownBlocksView extraction, task-notes markdown preview,
card depth + hover, warmer empty states), Phase 2 live Craft Notes editor
(TextKit-1 MarkdownTextView over pure NoteDecoration spans; slash menu;
byte-pinned BlockReorder + hover gutter; subpage cards). Phase 3 Daily Note
pinned/deferred. Verification: macOS CI run 28787673938 — 647 tests, 1
pre-existing skip, 0 failures. Eye pass on the editor is Leon's.
