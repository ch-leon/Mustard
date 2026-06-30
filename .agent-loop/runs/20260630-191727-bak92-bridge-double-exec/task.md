# BAK-92 — Bridge export re-issues a work order before its result is ingested

**Issue:** https://linear.app/bakinglions/issue/BAK-92
**Label:** Bug · **Related:** BAK-83 (Phase 2 bridge), BAK-73 (Phase 1 board)
**Branch:** `leon/bak-92-bridge-double-execution-guard`

## Problem (double-execution race)

The worker drains `_agent/outbox/<uid>.json`, archives it to `outbox/done/`, and
writes `_agent/results/<uid>.json`. The task stays `.queued`/`.forAgent` in Mustard
until the *next ingest tick* applies the result. In the window between
worker-archive and Mustard-ingest the task is still queued **with no live outbox
file**, so `BridgeExport.plan` re-issued the order. A worker running on the
duplicate executes the action twice (e.g. a second Gmail draft / Shortcut story).

## Fix

Add a **live-result guard** to the pure planner. `BridgeExport.plan` gains a
`liveResultUIDs: [String: Set<String>]` parameter; a uid with a live result is
suppressed in addition to a uid with a live outbox.

**Guard on LIVE `results/` only — never `results/done/`.** A `failed` result is
archived to `results/done/` while the task is left at its source stage, so the
next export *should* re-issue it (the intended retry path). Checking `results/done/`
would break retry and permanently suppress legitimately re-queued uids. Once a
`done` result is ingested, the task leaves `.queued`/`.forAgent` and the result is
archived together — so there is no window where (task still queued) AND (result in
done), and live-`results/` is the precise close of the race.

### Files
- `Sources/MustardKit/Logic/BridgeExport.swift` — `plan` adds `liveResultUIDs`
  param + suppression; defaulted to `[:]` so existing call sites are unaffected.
- `Sources/MustardKit/Agent/BridgeIO.swift` — protocol gains `liveResultUIDs`;
  `FileBridgeIO` lists `results/` top-level (non-recursive, excludes `done/`).
- `Sources/MustardKit/Agent/AgentService.swift` — `exportWorkOrders` passes
  `bridge.liveResultUIDs(...)` into the plan.
- Tests: 3 new `plan` cases + 1 service regression (StubIO gains `liveResults`).

## Acceptance criteria (from issue)
- [x] Export does not re-issue an order when a result already exists for that uid.
- [x] Retry path (`failed` result) preserved — re-issues after archive-to-done.
- [x] Idempotency lives on the Mustard export side (authoritative guard).

## Out of scope / follow-up
- Worker-side idempotency backstop (skip an order whose uid already has a result)
  lives in the connected-session worker (Phase 3), not this repo. Belt-and-braces;
  the export guard here is the authoritative fix. → candidate follow-up issue.
