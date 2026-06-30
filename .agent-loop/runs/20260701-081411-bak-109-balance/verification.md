# Verification — BAK-109
- **swift build** → Build complete (5.57s) ✅
- **swift test** → 407 pass / 1 skip / 0 failures ✅ (+4 WeekBalanceTests)
- **lint** → no-op ✅

## Acceptance
- [x] Balance lowers the peak day (LPT) across Mon–Fri; excludes done/meetings.
- [x] Undo restores each moved task's exact prior date.
- [x] "Already balanced" path when no moves; toast auto-dismisses.
- [x] Move preserves time-of-day.

## Notes
Leon to eyeball the Balance button, toast, and Undo restore.

## Review round 1 — CHANGES-REQUESTED → fixed
Blocking: greedy LPT could land on a peak ≥ the input peak (regression) while the
toast claimed success. **Fix:** `balance` now computes the current per-day peak and
returns an empty plan ("already balanced") unless the new peak is *strictly* lower —
so Balance can never increase load or churn for no gain. Added regression test
`test_balance_neverRegressesPeak_returnsEmptyWhenLPTWouldWorsen` (the {30,30}|{20,20,20}
case that LPT would push to 70) + `test_balance_excludesTasksOutsideWeekdays`.
swift test 409 pass / 1 skip / 0 failures (+6 WeekBalanceTests total).
