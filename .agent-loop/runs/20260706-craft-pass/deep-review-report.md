# Deep-review panel — Craft pass (PR #78, risk: HIGH)

Three adversarial skeptics, distinct lenses, each instructed to REFUTE a safety
claim by constructing a concrete failing sequence (code-reading only; no local
toolchain — CI verifies compilation/tests).

## Lens 1 — vault-file corruption & data loss: **REFUTED → fixed**

**Finding (real):** the NSTextView's window undo manager survived note
switches. Sequence: edit note A → switch to B (programmatic `string` replace
registers nothing and cleared nothing) → ⌘Z in B replays A's operation
(`shouldChangeText` validates length only) → B's buffer gains/loses foreign
bytes → save-on-switch persists the corruption to B's `.md`. Snapshot-before-
save made it recoverable, but it is a silent lossy rewrite.
**Fix (this run):** `undoManager?.removeAllActions()` in `updateNSView`'s
programmatic-replace branch — undo history is per-document; the branch only
fires on genuine document swaps (typing keeps binding and view equal).

Near-misses recorded as follow-ups (below): reorder EOF-terminator hygiene is
not self-inverse and injects a bare LF into pure-CRLF docs (whitespace-only,
bounded, multiset-pinned); a one-runloop ⌘S window during note switch could
save old content over the new ref (probabilistic, snapshot-caught).

## Lens 2 — undo integrity & interaction: **REFUTED → fixed**

**Finding (real):** `/Sub-page` created the file BEFORE the undoable splice —
⌘Z reverted the text but the file persisted, and each undo→retry minted a new
orphan `Untitled N.md`.
**Fix (this run):** slash commands are now pure text — `/Sub-page` splices a
dangling `[[Untitled]]`; creation happens only through the existing
user-confirmed create-from-dangling flow (which owns collision dedupe). The
`onCreateSubpage` plumbing was removed.

Near-misses recorded: undo can reopen the slash menu in a corner caret case;
IME marked-text interactions with menu commit are unverifiable without running;
selection-change writes menu state unguarded by `isProgrammaticUpdate` (saved
by ordering today — fragile).

## Lens 3 — regressions to existing surfaces: **UPHELD**

No `origin/main` behaviour broken. Save/selection/title/snapshot contracts in
NoteEditorView verified verbatim; Theme is additions-only; board drag, console
tap targets, backlinks toggle intact; `WikilinkURL` byte-identical to the old
scheme. Near-misses: failed note-create is now a silent no-op (was a visible
missing-file state); TaskDetailSheet feeds raw (frontmatter-unstripped) notes
to the block renderer (parity with old behaviour — latent); MarkdownPreviewView
is now dead code.

## Panel outcome

Two real findings, both fixed in this run (commits on the PR), one lens clean.
**Panel PASS after fix round** — consistent with prior high-risk runs (both
2026-06-29 entries also passed after one fix round). Verification: final CI run
on HEAD must be green before merge.

## Follow-ups (non-gating, for the backlog)

- BlockReorder terminator hygiene: make the added terminator EOL-aware (CRLF
  docs currently gain a bare LF) and consider self-inverse round-trip.
- Close the one-runloop ⌘S save window during note switch.
- Guard `textViewDidChangeSelection` with `isProgrammaticUpdate`; consider
  `hasMarkedText()` checks before menu trigger/commit.
- Surface failed note creation (silent no-op today).
- Strip frontmatter before block-rendering `task.notes` in TaskDetailSheet.
- Delete or repurpose the now-uncalled MarkdownPreviewView.
- Cache `NoteEditorView.metadataLine`'s file stat via `.task(id:)`.
