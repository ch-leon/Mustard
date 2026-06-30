# Verification — BAK-89

## Required checks (`.agent-loop/checks.yml`)

### `swift test`
```
Executed 347 tests, with 1 test skipped and 0 failures (0 unexpected) in 1.353s
```
347 pass / 1 skip. +2 tests vs prior 345.

### `swift build`
```
Linking Mustard
Build complete! (5.03s)
```
Executable links — the two view changes (TaskDetailSheet, MustardBoardCard) compile.

### `lint`
No linter configured (no-op per checks.yml).

## New tests (TDD — red before green)
- `BridgeExportTests.test_queuedTask_withoutActionType_isSkipped` — the guard.
- `BridgeExportTests.test_forAgentTask_withoutActionType_stillWritesPrep` — prep is
  exempt (empty action is expected for classification).

Red confirmed before implementing:
`test_queuedTask_withoutActionType_isSkipped … XCTAssertTrue failed`.

## UI (build + eye, per CLAUDE.md)
The Action picker and the "Needs an action type" card pill are verified by compile
only — the in-session shell has no Screen Recording/TCC, so the native app cannot be
screenshotted. **Leon to confirm visually:**
- Task detail → Action picker shows None / Draft email / Draft Slack / Shortcut
  ticket / Update vault, and persists the choice.
- A queued card with no action shows the amber "Needs an action type" pill; setting
  an action flips it to "Queued to run".
