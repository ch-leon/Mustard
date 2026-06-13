# Mustard — Agent Loop, Vault Source (Plan 2 of N)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Checkboxes track steps.

**Goal:** The spec's core loop with one source: sweep the Obsidian vault via `claude -p` → Recommendations queue (Approve / Deny / Schedule / Execute myself) → approved items execute via `claude -p` → every execution produces an OutputCard → Review queue (Accept / Revise / Discard).

**Architecture:** `ClaudeRunner` wraps `Process` spawning the subscription CLI (env-scrubbed of `ANTHROPIC_*`/`CLAUDE*`, stdin closed — lessons from TriageHub). It's injected as a closure so tests/integration use a stub binary. `Recommendation` and `OutputCard` are SwiftData models per spec §12 (deviation: no `AgentRun` yet — OutputCard hangs off Recommendation; invariant "one card per execution" still holds). `AgentService` (@MainActor, @Observable) orchestrates sweep/execute serially. UI adds a calm sidebar (Today | Agent) and an `AgentConsoleView` with the two queues.

**Vault path** is user-set via `@AppStorage("vaultPath")` + NSOpenPanel.

**Out of scope:** Slack/email/meeting sources, per-agent trust levels, gated-action interrupts mid-run, notch, hover panel, iOS, CloudKit.

## Tasks (condensed; full code lands in the Mustard repo)

1. **Models** — `Recommendation` (title, body, proposedActionType, decisionRaw `pending|approved|denied|scheduled|self`, createdAt, vaultPath, executionStateRaw `idle|running|finished|failed`) and `OutputCard` (content, kind, reviewRaw `pending|accepted|revised|discarded`, createdAt, recommendation?). Tests: defaults + decision transitions round-trip in memory. Commit.
2. **ClaudeRunner** — `struct ClaudeResult { ok, text, rateLimited }`; `typealias ClaudeRun = (String, String) async -> ClaudeResult` (prompt, cwd). Real impl: `Process` with `/usr/bin/env claude -p <prompt> --output-format json`, scrubbed env, `nullDevice` stdin, 15-min timeout, parse `{result, is_error}` JSON (fallback: raw stdout). Override binary via `MUSTARD_CLAUDE_BIN`. Test with a stub shell script fixture emitting canned JSON. Commit.
3. **Sweep prompt + parser** — `VaultSweep.prompt` asks for ≤5 recommendations as a JSON array `[{title, body, action_type}]`; `VaultSweep.parse(_:) -> [(title, body, actionType)]` extracts the first JSON array (code-fence tolerant). TDD the parser (happy path, fenced, garbage → []). Commit.
4. **AgentService** — `@MainActor @Observable final class AgentService`: `sweep(vaultPath:)` (insert pending Recommendations), `execute(_ rec:)` (state running → ClaudeRun in vault cwd → OutputCard + finished/failed), `decide(_ rec:, _ decision:)` (approved triggers execute; serial via an `isBusy` flag). Tests with stubbed ClaudeRun: sweep inserts, approve executes exactly one card, failure marks failed. Commit.
5. **UI** — `RootView` with calm sidebar (Today | Agent, hairline divider, bg `#FBFAF7`); `AgentConsoleView`: vault-path picker row, Sweep button with progress, RECOMMENDATIONS section (purple `#7F77DD` accents; verbs Approve · Deny · Schedule(+1d 9:00 as a MustardTask) · I'll do it(→ MustardTask inbox)), REVIEW section (green `#1D9E75`; output text, verbs Accept · Revise(re-execute) · Discard). Wire `MustardApp` to RootView + `.environment(agentService)`. Build, launch, commit.
6. **Integration verify** — stub binary end-to-end in-session (sweep → approve → card). Real `claude` run is user-verified from the Finder-launched app (session keychain limits, see memory).

**Done when:** tests green, app builds + launches with sidebar and console, stubbed loop produces an OutputCard that Accept marks accepted.
