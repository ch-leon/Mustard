# Deep-Review Panel — BAK-92 (PR #31)

High-risk adversarial panel. 3 independent fresh-context reviewers, each instructed to
default to BLOCK when uncertain. Diff range `8657865...HEAD`.

## Result: PASS (3/3 clear, no fix round)

| Lens | Verdict |
|------|---------|
| Correctness | **clear** |
| Security / Risk | **clear** |
| Spec-faithfulness | **clear** |

### Correctness — clear
Attacked 7 interleavings: the BAK-92 window (closed by the guard); tick overlap
(serialized — synchronous on MainActor under `!isSweeping/!isExecuting`); mid-tick
worker write (residual sub-ms exposure, inherent to a lock-free file bridge, not a
regression); permanent suppression (impossible — `ingestAgentResults` archives the
result for *every* outcome, so a live result never outlives one ingest pass);
failed-retry (preserved + tested); re-queued uid with old `done` result (not
suppressed — shallow listing); partial-write (fails toward *not* duplicating). No
double-issue or permanent-stranding path found.

### Security / Risk — clear
Diff performs no irreversible outward action (pure logic + non-mutating
`contentsOfDirectory` read + run-artifact markdown). Outward-action gating
(TrustPolicy / RecommendationAction.isGated) untouched; the guard runs downstream of
gating and can only *suppress* a write. uids are app-generated `UUID().uuidString`
used only as set-membership keys — no path-traversal/symlink surface. high escalation
justified and conservative (robot panel only). Non-blocking note: `liveResultUIDs`
fails open on a listing error (same `try?→[]` pattern as `liveOutboxUIDs`/`readResults`;
no worse than pre-fix status quo).

### Spec-faithfulness — clear
All acceptance criteria met. The deliberate deviation from the issue's "results/ OR
results/done/" suggestion is the *correct* reading: checking `results/done/` would
permanently strand every legitimately retried/re-queued uid — the narrower live-only
guard is the precise close of the race. No scope creep (one defaulted param + one
protocol method + wiring + a comment). Worker-side backstop is a legitimate
out-of-scope deferral (separate Phase-3 component).

## Non-blocking follow-ups raised by the panel (candidates, not blockers)
1. Distinguish "results/ dir absent (safe → [])" from "listing errored on an existing
   dir (unsafe)" in `liveResultUIDs` — fail-open hardening.
2. True exactly-once would need an atomic outbox claim or flipping the task off
   `.queued` at export time — future hardening; the guard + loop ordering shrink the
   window to a sub-ms synchronous gap, acceptable for a file bridge.
3. Worker-side idempotency backstop (Phase 3 connected-session worker).
