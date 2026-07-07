## Morning ritual — "Plan your day" wizard (BAK-50, morning half)

Implements the approved spec [`docs/specs/2026-07-06-morning-ritual-design.md`](../docs/specs/2026-07-06-morning-ritual-design.md) per the plan [`docs/superpowers/plans/2026-07-06-morning-ritual.md`](../docs/superpowers/plans/2026-07-06-morning-ritual.md). The starred build-order item I5 — the Sunsama-DNA daily ritual that plans your day and the agent's day together.

### What landed

- **Four-step wizard** (`MorningRitualView`, ~560pt sheet): **Rollover** (carry-forward now *stamps* what it moved; each rolled task gets Keep today / Tomorrow / Inbox with exclusive chosen-state rows) → **Agent standup** (inline mini-triage of pending recs via the existing `AgentService.decide`/`snooze`; Needs-Review count links to the console) → **Pick today** (inbox tap-to-add + passive capacity line reusing the Week calc) → **Focus** (star 1–3 tasks; cap counts open stars only).
- **Intentions = starred tasks**: `MustardTask.focusOnDay` (auto-expires at midnight — no cleanup); Today pins a FOCUS group above the timeline; the notch's idle rotation prefers the first open focus task.
- **Gentle-prompt entry**: calm Today banner (dismiss = gone for the day) + notch "Plan your day ✦" idle line — both gated by one pure `RitualPrompt.shouldOffer` rule — plus an *always-available* ⌘K "Plan my day" (deliberate re-entry affordance).
- **Data**: two optional CloudKit-safe `MustardTask` fields (`carriedForwardAt`, `focusOnDay`); two UserDefaults day-stamps. No new @Model, no claude invocations added, ritual-never-run leaves the app behaving exactly as before.

### Verification

- `swift test`: **576 tests, 0 failures** (1 pre-existing env-gated skip) — up from 556; 20 new tests, all pinned-time + injected UTC calendars.
- `swift build` clean; `./build-app.sh` assembles.
- Process: 7 plan tasks, each TDD'd by a fresh Opus implementer + two-stage review (4 review-driven fix commits: open-star focus cap, `plannedToday` extraction into Logic, standup copy, channel-key constant); whole-feature fresh-context review **PASS** (`.agent-loop/runs/20260706-morning-ritual/`).

### Risk

**Medium** (feature, `Sources/` only; zero high-risk paths — verified; wizard calls only existing decision APIs; no outward actions) → auto-merge per `.agent-loop/risk.yml`.

### Known limitations (accepted)

1. ⌘K re-planning is always available (only ambient prompts are `shouldOffer`-gated) — spec amended to record this.
2. Approving a `vaultNote` rec in the standup step triggers the existing console-parity claude execution path — spec amended to state this precisely.
3. FOCUS pins duplicate their tasks in the chronological timeline (deliberate; one-line filter if Leon dislikes it on sight).
4. Long-idle overnight windows show yesterday's banner state until the next render (notch self-corrects within its 4s tick).
5. Evening shutdown deliberately deferred — follow-up backlog issue filed on merge.

### Leon's eye-check (post-merge)

Banner placement + subtitle counts, wizard steps (esp. rollover chosen-states and the focus-cap hint), FOCUS group on Today, notch "Plan your day ✦" line and focus-title preference.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
