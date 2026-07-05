## Notes Phase A — vault-backed markdown notes with wikilinks & backlinks (BAK-145)

Implements the approved design spec [`docs/specs/2026-07-05-notes-vault-backlinks-design.md`](../docs/specs/2026-07-05-notes-vault-backlinks-design.md) (incl. its new pre-implementation Technical review addendum) per the plan [`docs/superpowers/plans/2026-07-05-notes-phase-a.md`](../docs/superpowers/plans/2026-07-05-notes-phase-a.md). Closes **BAK-146 → BAK-153** under epic **BAK-145**.

### What landed

- **Whole-vault scanner** — `NoteVaultIO` protocol on `FileVaultIO`: every `.md` across each enabled `SourceConfig` project, structural + agent-scratch pruning, `_filed/` kept visible; `write` now creates intermediate dirs (BAK-146).
- **Link graph** — pure `WikilinkIndex`: minimal YAML frontmatter (title/tags), `[[wikilink]]`/`[[T|alias]]`/`[[T#H]]`/`![[embed]]` extraction (fence-aware), deterministic resolution (exact-path-first, shortest-path-then-lexicographic, last-component fallback), forward/backlink graph with line snippets; single shared grammar in `WikilinkSyntax` (BAK-147).
- **SwiftData mirror** — `NoteIndexEntry` keyed `(project, relativePath)` (CloudKit-shaped defaults), rebuilt wholesale per project by `NoteIndexService` on a 300s throttle in the 60s app loop, on every save, and via ⌘K "Reindex notes now"; ⌘K "Go to Notes" added (BAK-148).
- **Notes tab** — peer to Today/Board/Week/Agent: project-grouped sidebar, real folder tree (`NoteTree`, pure + tested), filename/title filter with force-expand (BAK-149).
- **Editor** — plain monospaced source + rendered Preview (`MarkdownBlocks` parser + `AttributedString` inline), snapshot-before-save to `hub/.snapshots/`, honest dirty state on failed writes, save-on-switch so navigation never drops edits (BAK-150).
- **Backlinks panel** — collapsible, snippet rows recovered from content snapshots, tap-to-navigate (BAK-151).
- **Wikilink navigation** — preview taps resolve and navigate; unresolved targets offer "Create note" into the project's `notes/` (BAK-152).
- **"+" note creation** — per-project, sanitized/byte-clamped filenames with collision counters, YAML-safe frontmatter stub (BAK-153).

### Verification

- `swift test`: **535 tests, 0 failures** (1 pre-existing env-gated skip) — up from 447; ~88 new tests, one suite per Logic/Agent unit, pinned time + injected IO throughout.
- `swift build` clean; `./build-app.sh` assembles `build/Mustard.app`.
- Process: 9 tasks, each TDD'd by a fresh implementer and passed two-stage review (spec compliance + code quality) with 8 review-driven fix commits; whole-feature fresh-context review **PASS** (`.agent-loop/runs/20260705-notes-phase-a/`).

### Risk

**Medium** (feature work, `Sources/` paths; no high-risk paths touched, no irreversible outward actions) → auto-merge per `.agent-loop/risk.yml`. Full report: `.agent-loop/runs/20260705-notes-phase-a/risk-report.md`.

### Known limitations (accepted for Phase A)

1. Unsaved edits drop on tab-switch/app-quit (note→note switching is protected; explicit Save + dirty dot is the model).
2. Reindex rewrites a project's rows every 300s even when unchanged — needs a change-guard before CloudKit sync (N2).
3. Reindex/save file IO is synchronous on the main actor — fine at spec scale (hundreds of files).
4. Duplicate-title `[[links]]` resolve deterministic-first-match (spec-accepted); CRLF files won't parse frontmatter; index titles are H1-only.
5. Mobile note viewing is model-ready only until CloudKit (N2).

### Leon's eye-check (post-merge)

Views are build-verified per CLAUDE.md — please visually confirm: Notes tab layout/filter/tree, editor source+preview, resolved links blue vs dangling grey, backlinks panel, "+" sheet, create-from-unresolved alert.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
