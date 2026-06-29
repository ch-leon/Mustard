# Deep-review panel — Agent Task Board Phase 1 (PR #26, BAK-73)

**Date:** 2026-06-29 · **Risk:** high (agent core) · **Verdict: PASS** (3/3 clear after 1 fix round)

Diff: `6c0ee56...` → squash-merged as `9ad0f28` on `main`.

## Panel (3 independent fresh-context reviewers, default-to-block)

### Correctness — BLOCK → (re-review after fix) CLEAR
- **Blocker found:** `BoardMigration.backfill` runs every launch and derives stage from
  legacy `statusRaw`; in-app-created tasks were born `migratedStage = false` with
  `statusRaw = "inbox"`, so the backfill reverted any non-inbox stage to Inbox (data
  loss). Reviewer reproduced it with a failing test.
- **Fix:** `MustardTask.init` now sets `migratedStage = true` (in-app tasks are born
  stage-native; only pre-stage decoded rows migrate, once each). `runVaultNote` stages
  the task before the `isExecuting` guard so a race can't strand an approved rec.
  Regression test `test_backfill_doesNotClobberNewlyCreatedTaskStage` added.
- **Re-review:** CLEAR — confirmed SwiftData decode bypasses `init` (legacy rows still
  migrate), all creation sites covered, regression test fails without the fix.

### Security / risk — CLEAR
- `ClaudeRunner` / `TrustPolicy` / `RecommendationAction` untouched (confirmed via stat).
- Gated actions never auto-run (`test_applyTrust_neverTouchesGatedActions`); Phase 1 is
  staging-only — no executor drains `.queued`, nothing sends. Migration bounded/idempotent.
- No irreversible outward action in the diff.
- Note: schema change rides implicit SwiftData lightweight migration (fine for a local
  single-user store; a `VersionedSchema` would harden future model changes).

### Spec-faithfulness — CLEAR
- Owner-segmented column sets, decide routing, review-only-on-board, `stage` as source of
  truth, `someday` dropped — all match the spec/ADR. Out-of-scope items correctly absent.
- Note: the mock's `✦ Proposed` pill was intentionally not built (recs don't reach the
  board until decided — confirmed correct).

## Checks
`swift build` clean · `swift test` 315 pass / 1 skip / 0 fail (local). CI runs on the
self-hosted `mustard` runner.

## Follow-ups (non-blocking)
- BAK-82 — meeting-imported task titles are the full raw line (task-creation fix).
- `VersionedSchema` to harden future SwiftData model changes.
- A few minor board UI tweaks (Leon) — header alignment already fixed.
