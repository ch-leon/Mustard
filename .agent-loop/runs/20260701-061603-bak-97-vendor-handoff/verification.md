# Verification — BAK-97

## Required checks (.agent-loop/checks.yml)

### swift build
```
Build complete! (6.34s)
```
✅ pass

### swift test
```
Executed 366 tests, with 1 test skipped and 0 failures (0 unexpected) in 1.029s
Test Suite 'All tests' passed
```
✅ pass (no behaviour changed — docs-only — baseline suite green)

### lint
No linter configured (no-op per checks.yml). ✅ n/a

## Acceptance criteria
- [x] `docs/design/redesign-2026/` contains the four product files.
- [x] `support.js` / `ios-frame.jsx` NOT vendored.
- [x] `PRD.md` written; links each milestone/issue area to its prototype section.
- [x] Both parity discrepancies documented for BAK-98.

## Result
Done. Low-risk docs-only change; required checks green.
