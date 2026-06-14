# Mustard — Multi-Source Sweep (Plan 7 of N)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** Generalise the vault-only sweep into a small set of **per-source agents**
(Gmail, Shortcut, Jira) that each pull, filter to what Leon cares about, and drop
cards into the *same* pending `Recommendation` queue the vault sweep already feeds.
Each source runs on its own schedule. Everything downstream — review/approve gate,
confidence × trust auto-run, output cards, learning from edits — is unchanged.

**The loop (unchanged):** watch → suggest (action + confidence + inline draft) →
you approve/edit/reject → do → learn. This plan only widens *watch*.

## Scope now (v1 sources)

| Source | Surfaces | Filter |
|---|---|---|
| **Gmail** | Emails from a domain allow-list | sender domain ∈ allow-list (client domains **+ `@codeheroes.com.au`**) |
| **Shortcut** | Comments/tags mentioning me · new tickets | activity directed at me |
| **Jira** | Comments/tags mentioning me · new tickets assigned to me | activity directed at me |
| **Vault** | recent / stale / open-loop notes | *(existing `VaultSweep`, unchanged behaviour)* |
| **Slack** | — | deferred to a later plan |

Drafting **stays inline** in the sweep (proposals still carry `draft`). Splitting
DRAFT into its own deep-retrieval phase, multi-method fallback, and per-capability
executors are explicitly **out of scope** here — later plans.

## Prerequisite / risk (verify first)

`ClaudeRunner.run` shells `claude -p <prompt> --output-format json` with a
**scrubbed env** and **no `--mcp-config` / `--allowedTools`**. The Gmail/Shortcut/Jira
sources need those MCP tools available to the headless run. **Task 0:** confirm a
headless `claude -p` in the scrubbed env can reach the Gmail/Shortcut/Jira MCP
servers (they live in settings, not env, so they likely survive the scrub). If not,
extend `ClaudeRunner` to pass `--mcp-config`/`--allowedTools`. Do this before
writing source prompts — it gates everything else.

## Design

**`SourceAgent` protocol (`Agent/`, pure — like `VaultSweep` today):**

```swift
public protocol SourceAgent {
    var id: String { get }                      // "gmail" | "shortcut" | "jira" | "vault"
    var method: SourceMethod { get }            // v1: one method each (fallback list comes later)
    func prompt(config: SourceConfig) -> String // how to pull + filter for this source
    func parse(_ text: String) -> [VaultSweep.Proposal]   // stamps source / context / url
}

public struct SourceMethod: Equatable {        // structure supports multi-method later
    public let kind: String                     // "mcp" | "api" | "email" | "sheet"
}
```

- `VaultSweep` is reshaped to conform — **no behaviour change**, just adopts the protocol.
- New conformers: `GmailSource`, `ShortcutSource`, `JiraSource`, each owning its
  prompt (which encodes the filter) and a parser that stamps `source`,
  `sourceContext` (e.g. ticket key, thread subject), and `sourceURL`.

**Filtering is pure + tested, not just prompt text.** Each source has a pure
predicate so filtering is unit-testable independent of the model:
- `GmailSource.isClient(sender:allowList:)` → domain match (case-insensitive, sub-domain aware).
- Shortcut/Jira: the prompt scopes to "mentions me / assigned to me / new"; the
  parser drops anything that doesn't carry a `me`-directed marker.

**`SourceConfig` (settings, e.g. JSON in Application Support or UserDefaults):**
```
sources: [
  { id: "gmail",    enabled: true, intervalHours: 0.5, clientDomains: ["tmr.qld.gov.au", "thalesgroup.com", "codeheroes.com.au"] },
  { id: "shortcut", enabled: true, intervalHours: 1.0 },
  { id: "jira",     enabled: true, intervalHours: 1.0, userEmail: "leon@codeheroes.com.au" },
  { id: "vault",    enabled: true, intervalHours: 24.0 }
]
```

**`SweepScheduler` → per-source.** `isDue(lastSweptAt:intervalHours:now:)` stays the
pure primitive; add a per-source `lastSweptAt` keyed by source id (UserDefaults
`lastSweptAt.<id>`). The 60s app loop in `MustardApp` checks each enabled source.

**`AgentService.sweep()`** stops taking a single `vaultPath`. New
`sweepDueSources(config:now:)` iterates **enabled + due** sources **serially**
(one `claude -p` at a time — preserves the subscription-friendly invariant),
runs each source's prompt in the right cwd, normalises every proposal into a
`Recommendation` (stamping source fields), then runs `applyTrust` once at the end.

**`Recommendation` model:** **no changes** — `source`, `sourceContext`, `sourceURL`,
`confidence`, `reasoning`, `draft` already exist (Plan 6).

**UI:** minimal. A Settings section to manage the domain allow-list and per-source
enable + interval. The console already shows `source`; ensure source filter chips
cover the new ids. No new review UI (Plan 6 already built it).

## Tasks (TDD where logic)

0. **Verify headless MCP access** for Gmail/Shortcut/Jira; extend `ClaudeRunner`
   with `--mcp-config`/`--allowedTools` only if needed (+test against stub binary).
1. **`SourceMethod` + `SourceAgent` protocol**; reshape `VaultSweep` to conform
   (+test: vault prompt/parser unchanged).
2. **`SourceConfig`** model + load/save + defaults (+tests: round-trip, defaults).
3. **`GmailSource`** prompt + parser + `isClient(sender:allowList:)` predicate
   (+tests: domain match incl. codeheroes, sub-domains, non-client rejected).
4. **`ShortcutSource`** + **`JiraSource`** prompts + parsers + me-directed filter
   (+tests: mention/assigned kept, unrelated dropped; source/url stamped).
5. **Per-source `SweepScheduler`** keying + `AgentService.sweepDueSources`
   serial iteration + normalisation (+tests with stubbed `ClaudeRun`).
6. **`MustardApp`** 60s loop → check each enabled source; **Settings UI** for
   allow-list + per-source enable/interval. Build / relaunch / commit.

## Done when

- `swift test` green; vault sweep behaviour unchanged.
- Enabling Gmail surfaces only allow-listed-domain emails as pending cards with
  source = `gmail`, context, and a working `sourceURL`.
- Shortcut/Jira surface only me-directed comments/tags and new/assigned tickets.
- Each source sweeps on its own interval; runs stay serial (one `claude` at a time).
- Slack remains absent. No downstream review/trust/output behaviour changed.
