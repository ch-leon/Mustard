## BAK-84 — Agent bridge: archive undecodable result files (+ Part 1 obsolescence)

Two BAK-83 deep-review follow-ups. Verified the current code first — scope changed.

### Part 2 (DONE) — quarantine undecodable results
A malformed `_agent/results/*.json` was dropped by `readResults` (`try?`/compactMap) but never moved aside, so it was silently re-scanned every ~10-min loop.
- **`BridgeIO.quarantineUndecodableResults(workingDir:) -> Int`** (+ `FileBridgeIO` impl): moves any undecodable / empty-uid `.json` — the *exact* keep-criterion `readResults` uses — into `results/quarantine/`. Non-recursive listing excludes the `done/` + `quarantine/` subdirs.
- **`BridgeFolders.resultsQuarantine`** added.
- **`AgentService.ingestAgentResults`** calls it each run, *after* applying + archiving the good ones — so a valid/pending result (incl. the BAK-92 live-result) is structurally never seen by the scan.

### Part 1 (OBSOLETE) — route via AreaRouter
The issue asked to route the loop through `AreaRouter.workingDirectory` instead of `MeetingTaskSync.defaultAreaMap`. **BAK-87 already reworked this:** `MustardApp`'s loop uses each enabled `SourceConfig`'s own `workingDirectory` + `AreaMapping.areaName(forProject:)` — it no longer reads `defaultAreaMap`, and `AreaRouter` is dead code. Re-routing through it would *discard* each source's configured dir (a regression). So Part 1 is moot; I only refreshed the stale `exportWorkOrders` doc-comment. Dead-`AreaRouter` removal → filed as **BAK-96**.

### Tests (TDD, red→green)
- `FileBridgeIOTests` (4): moves undecodable+empty-uid / keeps valid, no-dir→0, all-valid→0, rerun-clobber idempotency.
- `AgentBridgeServiceTests.test_ingest_quarantinesUndecodableResults`: ingest invokes quarantine once.

### Checks
- `swift test` → 366 pass / 1 skip (+5 tests)
- `swift build` → clean

### Risk
Medium (`Improvement`; Logic + BridgeIO + a one-line `ingestAgentResults` call). No outward action — quarantine relocates a local file Mustard already ignores. Not escalated to high (no dispatch/gating logic).

### Review
Fresh-context review: **no blockers**, recommend merge. Part-1 obsolescence independently verified; keep-criterion parity confirmed exact. Its one suggestion (rerun idempotency test) is in commit `45ba930`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
