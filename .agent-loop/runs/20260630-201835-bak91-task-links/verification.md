# Verification — BAK-91

## Required checks (`.agent-loop/checks.yml`)

### `swift test`
```
Executed 359 tests, with 1 test skipped and 0 failures (0 unexpected) in 1.057s
```
359 pass / 1 skip. +7 tests vs prior 352 (6 extractor + 1 integration).

### `swift build`
```
Linking Mustard
Build complete! (5.01s)
```
Executable links — the TaskDetailSheet Links section compiles.

### `lint`
No linter configured (no-op per checks.yml).

## New tests (TDD — red before green)
- `TaskLinkExtractorTests` (6): Shortcut label, Jira label, dedupe across texts,
  multi-link first-occurrence order, ignores non-http/empty, generic→host label.
- `AgentTests.test_approve_createTask_capturesReferencedLink`: approving a create_task
  rec with a Shortcut URL lands a task with `links == [that URL]` (label "Shortcut")
  and `sourceURL` carried.

Red confirmed before implementing (`TaskLinkExtractor` type absent).

## UI (build + eye, per CLAUDE.md)
Build-verified only. **Leon to confirm visually:** TaskDetailSheet shows a Links
section listing carried links; clicking opens; the × removes; pasting a URL + Enter
(or +) adds it (http/https only, deduped).
