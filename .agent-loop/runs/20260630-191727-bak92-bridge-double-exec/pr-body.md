## BAK-92 — Bridge export re-issues a work order before its result is ingested (double-execution race)

Fixes the duplicate-order race seen live during the BAK-73 board test.

### Problem
The worker drains `_agent/outbox/<uid>.json`, archives it to `outbox/done/`, and writes `_agent/results/<uid>.json`. The task stays `.queued`/`.forAgent` in Mustard until the *next ingest tick*. In the window between worker-archive and Mustard-ingest the task is still queued **with no live outbox file**, so `BridgeExport.plan` re-issued the order — and a worker running on the duplicate executes the action twice (e.g. a second Gmail draft / Shortcut story).

### Fix
`BridgeExport.plan` gains a `liveResultUIDs` parameter and now suppresses a write when a **live result** exists for the uid, in addition to a live outbox.

Guards on **live `results/` only — never `results/done/`**: a `failed` result is archived to `results/done/` while the task is left at its source stage, so the next export *should* re-issue it (the intended retry path). Checking `results/done/` would break retry and permanently suppress legitimately re-queued uids. Because ingest changes the task stage and archives the result together, there is no window where (task still queued) AND (result in done) — so live-`results/` is the precise close of the race.

### Changes
- `BridgeExport.plan` — new `liveResultUIDs: [String: Set<String>] = [:]` param + suppression (defaulted, so existing call sites are unaffected).
- `BridgeIO` protocol + `FileBridgeIO.liveResultUIDs` — non-recursive listing of `results/` (excludes `done/`).
- `AgentService.exportWorkOrders` — feeds `bridge.liveResultUIDs(...)` into the plan.

### Tests (TDD, red→green)
- `BridgeExportTests`: `test_queuedTask_withLiveResult_isSkipped`, `test_liveResultForOtherUID_doesNotSuppress`, `test_liveResultInOtherDir_doesNotSuppress`.
- `AgentBridgeServiceTests`: `test_export_skipsQueuedTask_whenLiveResultPending` (service-level regression).

### Checks
- `swift test` → 345 pass / 1 skip (+6 tests)
- `swift build` → clean

### Review
Fresh-context review: **APPROVE, no blockers** (standards/spec/test PASS). Its three non-blocking follow-ups (document export-before-ingest ordering; lock the failed-retry contract with a test; assert prep-mode suppression) are addressed in commit `cf00405`.

### Risk
High (escalated — agent work-dispatch correctness path). No irreversible outward action performed by this change → robot deep-review panel, no human gate.

### Follow-up (non-blocking)
Worker-side idempotency backstop (skip an order whose uid already has a result) lives in the connected-session worker (Phase 3), not this repo — belt-and-braces; the export guard here is the authoritative fix.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
