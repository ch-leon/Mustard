# Verification — BAK-92

## Required checks (`.agent-loop/checks.yml`)

### `swift test`
```
Executed 345 tests, with 1 test skipped and 0 failures (0 unexpected) in 0.467s
```
345 pass / 1 skip (baseline skip). +6 tests vs prior 339 (4 initial + 2 review-hardening).

### `swift build`
```
Building for debugging...
Build complete! (0.29s)
```

### `lint`
No linter configured for Mustard (no-op per checks.yml).

## New tests (TDD — red before implementation, then green)
- `BridgeExportTests.test_queuedTask_withLiveResult_isSkipped` — the race guard.
- `BridgeExportTests.test_liveResultForOtherUID_doesNotSuppress` — narrow scoping.
- `BridgeExportTests.test_liveResultInOtherDir_doesNotSuppress` — dir scoping.
- `AgentBridgeServiceTests.test_export_skipsQueuedTask_whenLiveResultPending` —
  service-level regression mirroring the live scenario (outbox archived, result
  pending ingest → no re-issue).

Red confirmed before implementing: `error: extra argument 'liveResultUIDs' in call`.

## Manual / live
Not run from this session (the headless shell cannot drive the native app). The
race is now covered by deterministic unit tests; a live re-test would approve a
`draft_email`/`ticket` rec, let the worker write a result, and confirm no duplicate
`outbox/<uid>.json` reappears before ingest.
