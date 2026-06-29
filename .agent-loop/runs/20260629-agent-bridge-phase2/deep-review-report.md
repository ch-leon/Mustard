# Deep-review panel — Agent Bridge Phase 2 (PR #27, BAK-83)

**Date:** 2026-06-29 · **Risk:** high (touches AgentService) · **Verdict: PASS** (3/3 clear, no fix round)

Diff: `main...` → squash-merged as `fe3b5b1` on `main`.

## Panel (3 independent fresh-context reviewers, default-to-block)

### Correctness — CLEAR
- `liveOutboxUIDs` correctly excludes `done/` (non-recursive list + `.json` filter).
- Ingest archives in ALL outcomes → nothing re-applies; stage guard + double-apply no-op verified by tests.
- `failed` leaves the task at its source stage; the outbox order was already archived by the session, so the next export re-issues (correct retry, no clobber).
- Stale-cancel is sound under the project↔area bijection; loop calls sit behind `!isSweeping && !isExecuting` + the 600s throttle.

### Security / risk — CLEAR
- `ClaudeRunner` / `TrustPolicy` / `RecommendationAction` untouched. Bridge does no execution/send — file I/O only; ingest only mutates board state. Phase 2 stays staging-only.
- Writes scoped to `<workingDir>/_agent/`; filenames are UUID `<uid>.json` (no path traversal); the only deletes are Mustard's own outbox files + an archive-collision overwrite. Malformed/unknown result files are dropped/no-op safely. No irreversible action.

### Spec-faithfulness — CLEAR
- Folder protocol, both schemas, the full apply table, export purity (mobile constraint), and the ~10-min trigger all match the spec. Out-of-scope correctly absent: no Phase 3 worker, no real connector execution. Contract doc + manual test present.

## Checks
`swift build` clean · `swift test` 334 pass / 1 skip / 0 fail (local).

## Follow-ups (non-blocking)
- Route the loop through `AreaRouter.workingDirectory` (vs `defaultAreaMap` directly) to match the doc and pick up the `workVaultRoot` fallback for unconfigured KBs.
- Archive (or quarantine) an undecodable `_agent/results/*.json` so it isn't re-read every loop.
- `prep·done` replaces `task.notes` wholesale (discards edits made while `forAgent`) — spec-conformant; revisit if it bites.
