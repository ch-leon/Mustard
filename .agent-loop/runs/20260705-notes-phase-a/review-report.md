# Fresh-context review — Notes Phase A (BAK-145)

**Verdict: PASS (mergeable).** Reviewer ran `swift test` (535, 0 failures, 1
pre-existing skip) and `swift build` (clean) independently.

## Axes (per .agent-loop/review-rubric.md)

- **Standards: pass.** Decision logic in Logic/ or injected-IO Agent/; views render
  + dispatch only; Theme tokens throughout (direct font sizes are plan-mandated or
  mirror existing precedent); no unrelated refactors — all 34 touched files map to
  the plan. WikilinkSyntax hoist praised as anti-drift.
- **Spec: pass.** All spec sections + all 6 addendum items implemented; no Phase B/C
  leakage (no task_id/area writes, no full-text search, no rich editor, no backlink
  materialization); `_filed/` visible; multi-project keying throughout. Beyond-plan
  hardenings (path-qualified create, byte clamp, YAML quoting) documented in code.
- **Risk: pass — MEDIUM.** No high-risk paths (ClaudeRunner/TrustPolicy/
  RecommendationAction/auth untouched, verified by grep); no irreversible outward
  actions; path-escape audit clean (sanitized filenames, resolution only maps to
  scanned candidates — `[[../../etc]]` is not a vector).
- **Test: pass.** 447 → 535, one suite per unit, pinned time, injected IO. Views
  build-verified per CLAUDE.md; Leon's eye-check is the known post-merge step.

## Process note

Each of the 9 implementation tasks was built by a fresh Opus subagent (TDD) and
passed a two-stage review (independent spec-compliance, then code-quality) with
fix rounds: 8 review-driven fix/hardening commits landed across the feature.

## Known limitations (recorded in PR + digest)

1. Unsaved edits drop on tab-switch/app-quit (note→note switches are protected;
   dirty dot + explicit Save is the model).
2. Reindex rewrites all of a project's rows every 300s even when unchanged — fine
   locally, needs a change-guard before CloudKit (N2) or it becomes sync traffic.
3. Reindex + editor save do synchronous file IO on the main actor — fine at
   hundreds of files, degrades on ballooned folders.
4. Duplicate-title resolution = deterministic first match (spec-accepted); CRLF
   files won't parse frontmatter; index title is H1-only vs editor header's H1–H6.
5. Mobile viewing is model-ready only until CloudKit (N2) lands.

## Non-blocking follow-ups (ticket-worthy)

- Autosave or onDisappear save in NoteEditorView (biggest payoff).
- Skip no-op reindexes by comparing modificationDate against stored lastModified.
- Extract the save-flow decision (dirty gate/baseline rule) into a pure Logic unit.
- Unify title derivation (index H1-only vs editor H1–H6).
- Move reindex file reads off the main actor when vault sizes grow.
