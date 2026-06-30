# BAK-84 — Agent bridge: route via AreaRouter + archive undecodable result files

**Issue:** https://linear.app/bakinglions/issue/BAK-84 · **Label:** Improvement
**Branch:** `leon/bak-84-bridge-arearouter-archive` (isolated worktree)

Two BAK-83 deep-review follow-ups. Verified current code first (build-order/issues lag
the code) — scope changed:

## Part 1 — route via AreaRouter → **OBSOLETE, not done (documented)**
The issue asked to route the bridge loop through `AreaRouter.workingDirectory` instead
of reading `MeetingTaskSync.defaultAreaMap` in `MustardApp`. **BAK-87 already reworked
this:** MustardApp's loop now iterates each enabled `SourceConfig` and uses its own
`workingDirectory` + `AreaMapping.areaName(forProject:)` — it no longer reads
`defaultAreaMap` at all, and `AreaRouter` is dead (referenced only by its own tests +
one stale comment). Routing back through `AreaRouter` would be a regression toward the
retired map. So Part 1 is moot; I refreshed the stale `exportWorkOrders` doc-comment
that still referenced "AreaRouter map". (Removing dead `AreaRouter` + its tests is a
separate cleanup — noted as a follow-up candidate, not bundled here.)

## Part 2 — quarantine undecodable results → **DONE**
A malformed `_agent/results/*.json` was dropped by `readResults` (`try?`/compactMap) but
never moved aside, so it was silently re-scanned every ~10-min loop.
- New `BridgeIO.quarantineUndecodableResults(workingDir:) -> Int` (+ `FileBridgeIO` impl):
  moves any undecodable / empty-uid `.json` (same keep-criterion as `readResults`) into
  `results/quarantine/`. Non-recursive listing excludes the quarantine subdir.
- `BridgeFolders.resultsQuarantine` added.
- `AgentService.ingestAgentResults` calls it each run, after applying/archiving the good ones.

### Files
- `Sources/MustardKit/Logic/BridgeProtocol.swift` — `resultsQuarantine` folder.
- `Sources/MustardKit/Agent/BridgeIO.swift` — protocol method + `FileBridgeIO` impl.
- `Sources/MustardKit/Agent/AgentService.swift` — call in `ingestAgentResults`; comment refresh.
- Tests: `FileBridgeIOTests` (3) + `AgentBridgeServiceTests` (1, StubIO conformance).

## Acceptance criteria
- [x] Undecodable result files moved aside, not re-read every loop.
- [~] Route via AreaRouter — obsolete post-BAK-87; documented, comment refreshed.
