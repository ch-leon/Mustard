# Fresh-context review — Craft pass (PR #78)

Reviewed cold (separate agent context, no involvement in the build) against
`.agent-loop/review-rubric.md`, the spec, both plans, and the full
`origin/main...HEAD` diff.

## Standards review: PASS

- Markdown-as-truth verified structural: `NoteDecoration` exposes only
  range-producing APIs; partition built via `getLineStart` (CRLF-safe); the
  round-trip guard covers a fixture battery beyond the plan's.
- Only two source-producing functions (`BlockReorder.move`,
  `SlashMenu.insertion`), both byte-pinned; the every-valid-move multiset
  battery means no content line can be lost/duplicated/edited by reorder.
- Undo integrity: decorations attribute-only inside begin/endEditing (outside
  undo); both text mutations through `insertText(_:replacementRange:)` with
  `breakUndoCoalescing`; smart substitutions all disabled.
- Save semantics (snapshot-before-save, failed-write-stays-dirty, baseline
  rule, save-on-switch, reindex-on-save) verified line-by-line unchanged.
- Theme tokens only (NS bridges derive from `Theme.Palette`); Logic TDD'd with
  pinned UTC; recorded drift notes present at each divergence.

## Spec review: BLOCK → remediated in this run

1. **Plan Task 11 undelivered** (stale CLAUDE.md layout + "535 tests";
   missing build-order entry) → **fixed**: CLAUDE.md folder map + test count
   updated; `F22` appended to `docs/build-order.md`.
2. **Unrecorded High→medium risk downgrade** — spec marks Phase 2 High
   (NSTextView); plan expects the `deep-review` panel → **remediated by
   running the panel** (see `deep-review-report.md`) and correcting
   `risk-report.md` to High.
3. **Unrecorded process drift** — single PR instead of the planned three
   (Leon's explicit "build the whole thing" directive, now recorded);
   `trace.jsonl` absent because this run was driven from Claude Code remote
   rather than the dev-loop plugin (no trace emitter exists there) — recorded
   here rather than fabricated.

## Non-blocking findings (follow-ups, not gates)

- `NoteEditorView.metadataLine` stats the file per body evaluation; cache via
  `.task(id:)`.
- Gutter "+"-opened slash menu is pick-only (closes on first typed char) —
  comment or eye-check.
- Sub-page creation not undoable as a unit (⌘Z removes text; created file
  remains as a harmless orphan).
- `NoteDecoration` ordered-list marker spans could skew (styling-only) on
  surrogate-pair digits.
- `BlockGutterOverlay` drop-slot math is an untested view seam — candidate
  test seam if drag bugs surface.
