# Verification — BAK-84

## Required checks (`.agent-loop/checks.yml`)

### `swift test`
```
Executed 365 tests, with 1 test skipped and 0 failures (0 unexpected) in 1.128s
```
365 pass / 1 skip. +4 tests vs prior 361.

### `swift build`
```
Build complete! (0.29s)
```

### `lint`
No linter configured (no-op per checks.yml).

## New tests (TDD — red before green)
- `FileBridgeIOTests.test_quarantine_movesUndecodable_keepsValid` — garbage + empty-uid
  files move to `results/quarantine/`; the valid result stays and is still read.
- `FileBridgeIOTests.test_quarantine_noResultsDir_returnsZero`.
- `FileBridgeIOTests.test_quarantine_allValid_movesNothing`.
- `AgentBridgeServiceTests.test_ingest_quarantinesUndecodableResults` — ingest invokes
  quarantine once (StubIO counter).

## No UI in this change
Pure file-IO + a one-line wiring; no view changes, so nothing for Leon to eyeball.
