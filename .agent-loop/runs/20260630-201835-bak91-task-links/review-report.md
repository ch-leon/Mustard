# Fresh-context review — BAK-91

Independent fresh-context reviewer, `origin/main...HEAD` (isolated worktree), four axes.

## Verdict: NO BLOCKERS — ship-able

| Axis | Verdict |
|------|---------|
| Standards | PASS — pure logic in `Logic/`; view reuses `TaskLinkExtractor.label`; `Theme` tokens used; `TaskLink` reused; tight diff. |
| Spec | PASS — all three deliverables wired (extractor / materializeTask carries links+sourceURL / Links section). Carrying sourceURL mirrors the existing `materialize` path — not scope creep. |
| Risk | LOW — pure logic + one view + a 2-line orchestrator change; no outward/irreversible/schema/network. |
| Test | PASS — extractor + the real `decide` path asserted through public interfaces; sourceURL↔draft dedupe incidentally covered. |

Reviewer empirically probed NSDataDetector edge cases and the manual-add UX:
- `defer { newLinkURL = "" }` placement is correct (invalid non-URL input is preserved
  to fix; valid duplicate clears) — acceptable UX.
- `ForEach id: \.url` duplicate-id risk effectively nil (both paths dedupe by exact
  string; `URL.absoluteString` doesn't renormalize typical inputs).

## Findings
1. **Host-substring label false positives** (`contains("shortcut.com")` matched
   `notshortcut.com.evil.example`; `contains("jira")` matched `mycompany.jira.example.com`).
   Cosmetic (label only; link still opens). → **ADDRESSED** (commit a07e461): match on
   host boundaries (`== / hasSuffix(.shortcut.com)`, `.atlassian.net` suffix, first host
   label `jira`) + 2 regression tests.
2. (non-blocking, addressed-by-1) — n/a.
3. ForEach id risk — not a concern (see above).

UI is build-verified only (CLAUDE.md) — Leon to visually confirm the Links section.
