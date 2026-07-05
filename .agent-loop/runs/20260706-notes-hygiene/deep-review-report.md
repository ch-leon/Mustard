# Deep-Review Report — PR #76 (chore/notes-hygiene-bak71)

Run: 20260706-notes-hygiene
PR: https://github.com/ch-leon/Mustard/pull/76
Scope: Notes Phase A hygiene follow-ups + BAK-71 calendar polish

## Panel verdicts

| Lens | Verdict | Summary |
|------|---------|---------|
| Correctness | **BLOCK** | Three blockers + two minors against the reindex change-guard and title unification (findings below) |
| Security | CLEAR | Independently flagged the reindexAll guard bypass (finding 1) and noted mtime granularity as a residual, acceptable risk |
| Spec | CLEAR | All 4 mandate items delivered (change-guard, title unification, CRLF, BAK-71 sub-items); no scope creep |

## Correctness findings (blockers)

1. **`reindexAll` must force.** The manual ⌘K "Reindex notes now" path routed
   through the same change-guard as the scheduled loop, so a user's explicit
   rebuild request could silently no-op. Fix: `force: Bool = false` on
   `reindex(project:workingDirectory:now:force:)`; `reindexAll` passes
   `force: true`, bypassing the guard entirely.

2. **Parser-version salt.** The guard compares only (path, mtime); a shipped
   parser change alters DERIVED rows without touching bytes on disk — this very
   PR's any-heading-title and CRLF fixes would never reach already-indexed
   notes. Fix: `NoteIndexService.parserVersion` (bumped to 2) checked against
   an injected `UserDefaults` key (`noteIndexParserVersion`) on init; a
   mismatch disables the guard for the whole session (all projects rebuild
   within the first loop tick) and writes the new version immediately so the
   next launch trusts the guard again.

3. **TOCTOU: stat-before-read.** The rebuild re-statted each file AFTER reading
   its content, so a write landing between read and stat stamped a NEWER mtime
   than the content actually read — the guard would then skip that racing write
   forever. Fix: the stored `lastModified` reuses the mtimes captured in the
   pre-pass `disk` map (stat BEFORE read); a racing write yields disk ≠ stored
   on the next tick → rebuild (the safe direction).

## Correctness findings (minor, folded in)

4. **`NoteReindexScheduler.isUnchanged` duplicate disk paths.** The pure
   contract permitted duplicate disk paths that could mask a removed file
   (counts match, every disk entry finds a stored match). Fixed with a
   uniqueness check on the disk path set.

5. **`WikilinkIndex.firstHeading` leading whitespace.** The comment claimed
   parity with NoteEditorView's header scan, but the editor trims the line
   before counting hashes and the index did not — `"  ## Foo"` diverged. Fixed
   by trimming before counting, making the claimed parity true.

## Security notes (clear, recorded)

- reindexAll guard bypass: same as correctness finding 1; resolved by the force path.
- mtime granularity: filesystem mtime resolution could in principle mask a
  same-instant rewrite; accepted — the editor save path calls `reindex`
  directly after write, and the manual force path exists as an escape hatch.

## Resolution

All findings fixed in commit `fix(notes): force-path + parser-version salt +
stat-before-read for reindex guard (BAK-145 hygiene)` on this branch, TDD
(failing tests first), full `swift test` + `swift build` green.

Test adjustments beyond new coverage, each justified:
- `NoteIndexServiceTests` constructions now inject a fresh in-memory
  `UserDefaults` suite (pre-seeded with the current parser version). Required
  by finding 2: with `.standard`, the first service constructed in a fresh
  test process would see a version mismatch, disable its guard, and make the
  skip tests order-dependent — and tests would mutate the runner's real
  defaults. No assertion was weakened; no test was invalidated by finding 3's
  stat-source change (the existing `lastModified` assertion sets the mtime
  before reindex, so pre-read and post-read stats agree there).
- `FakeNoteIO` gained an `onRead` hook so the TOCTOU test can model a writer
  racing the rebuild.
