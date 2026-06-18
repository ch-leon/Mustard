# Mustard — Multi-Source Sweep (Plan 7 of N)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.
> **Design spec:** `docs/specs/2026-06-15-source-ingestion-foundation.md`.

**Goal:** Generalise the vault-only sweep into an **email-led source ingestion
foundation**: Gmail discovery finds direct client emails plus Jira/Shortcut
notification emails, gathers bounded context from the vault, dedupes, and drops
cards into the *same* pending `Recommendation` queue the vault sweep already
feeds. The sweep may run many times per day without duplicating cards. Everything
downstream — review/approve gate, confidence × trust auto-run, output cards,
learning from edits — is unchanged.

**The loop (unchanged):** watch → suggest (action + confidence + inline draft) →
you approve/edit/reject → do → learn. This plan only widens *watch*.

**New ingestion invariant:** source sweeps are **idempotent**. The same external
event can be seen repeatedly by lookback windows, MCP search, or retries, but it
must create at most one `Recommendation` per external event (keyed on `sourceEventID`).

## Scope now (v1 sources)

| Source | Surfaces | Filter |
|---|---|---|
| **Gmail** | Emails from a domain allow-list | sender domain ∈ allow-list (client domains **+ `@codeheroes.com.au`**) |
| **Gmail Jira notifications** | Jira notification emails | ticket activity directed at me |
| **Gmail Shortcut notifications** | Shortcut notification emails | story activity directed at me |
| **Vault** | recent / stale / open-loop notes | *(existing `VaultSweep`, unchanged behaviour)* |
| **Google Sheets / Slack / Shortcut direct / Atlassian direct** | — | optional context only; not v1 sweep discovery |

Sweeps may include a **preview draft**, but recommendations must be context-
grounded: before emitting a card, the email sweep should inspect the email/thread
and bounded vault context for matching defect ids, ticket keys, client/project
names, or other clear identifiers. Approved execution performs retrieval again
before producing the final `OutputCard`. Sending email, filing tickets, and
outward actions remain out of scope.

## Prerequisite / risk — RESOLVED

The Gmail transport is settled (see **ADR-0007** +
`docs/specs/2026-06-15-thin-cloud-scout.md`):

- Mustard's local `ClaudeRunner` (`claude -p`, scrubbed env, closed stdin)
  **cannot reach Gmail.** Empirical probe returned `NONE`: the Gmail/Slack/Calendar
  entries in `claude mcp list` are **claude.ai account connectors**, not local CLI
  MCP servers a standalone app inherits.
- A **Claude Code routine** can: verified 2026-06-15 — a scheduled routine read
  Gmail via the connector (55 threads/24h) and pushed to a private repo. Routines
  include 25 runs/rolling-24h free (hourly = 24/day, no metered billing).
- **Decision:** Gmail discovery is delivered by the **thin-scout cloud routine**,
  which writes candidate `SourceProposal`s into a Git-synced vault `_inbox/`; the
  Mac ingests them read-only via `InboxIngest`. The Mustard-owned Gmail OAuth build
  is **dropped**. SwiftData stays the source of truth (ADR-0001); execution stays
  on the Mac (ADR-0003).

## Design

**`SourceAgent` protocol (`Agent/`, pure — like `VaultSweep` today):**

```swift
public enum SourceID: String, Codable, CaseIterable {
    case gmail
    case vault
}

public protocol SourceAgent {
    var id: SourceID { get }
    var method: SourceMethod { get }            // v1: one method each (fallback list comes later)
    func prompt(config: SourceConfig, state: SourceState, now: Date) -> String
    func parse(_ text: String, config: SourceConfig) -> [SourceProposal]
}

public struct SourceMethod: Equatable {        // structure supports multi-method later
    public let kind: String                     // "mcp" | "api" | "email" | "sheet"
}

public struct SourceProposal: Equatable {
    public let source: SourceID
    public let sourceItemID: String             // stable parent id: email thread or note hash
    public let sourceEventID: String            // stable event id: message id or note hash
    public let sourceContext: String            // human-readable provenance
    public let sourceURL: String?
    public let occurredAt: Date?
    public let title: String
    public let body: String
    public let actionType: String
    public let confidence: Double
    public let reasoning: String
    public let draft: String
}
```

- `VaultSweep` is reshaped to conform — **no behaviour change**, just adopts the
  protocol and maps existing vault suggestions into `SourceProposal`.
- **Gmail discovery is NOT a local `SourceAgent`.** Per ADR-0007 it is delivered by
  the thin-scout cloud routine (`docs/specs/2026-06-15-thin-cloud-scout.md`): the
  routine writes candidate `SourceProposal`s (direct client emails + Jira/Shortcut
  notification emails) to the vault `_inbox/`, and a new Mac-side `InboxIngest`
  reads → validates (allow-list enforced here) → dedupes → inserts. `VaultSweep`
  remains the one local `SourceAgent`.

**`Recommendation` model changes (minimal provenance fields):**

```swift
public var sourceItemID: String?
public var sourceEventID: String?
public var occurredAt: Date?
```

Keep existing `source`, `sourceContext`, and `sourceURL`. **Dedupe identity**
(`sourceItemID`, `sourceEventID`) must stay structured and queryable — never
packed into `sourceContext`. Non-identity provenance (e.g. the Jira/Shortcut
notification system) may live in `sourceContext` for v1; promote it to its own
column only if you need to filter cards by it.

**Filtering is pure + tested, not just prompt text.** Prompts must request enough
raw metadata for parsers to enforce the rule. Each source has a pure predicate so
filtering is unit-testable independent of the model:
- `GmailSource.isClient(sender:allowList:)` → domain match (case-insensitive, sub-domain aware).
- Jira/Shortcut notification emails: prompts scope to "mentions me / assigned to
  me / new"; parsers drop anything that does not carry a `me`-directed marker or
  a configured notification signal.

Required prompt output metadata:

```json
{
  "source_item_id": "thread-id",
  "source_event_id": "message-id",
  "source_url": "https://...",
  "source_context": "PROJ-123 · new comment from Alice",
  "occurred_at": "2026-06-15T02:10:00Z",
  "sender_email": "person@client.com",
  "sender_domain": "client.com",
  "notification_system": "jira",
  "ticket_key": "PROJ-123",
  "mentioned_me": true,
  "assigned_to_me": false,
  "event_type": "comment_mention",
  "title": "short imperative title",
  "body": "1-3 sentences: what and why",
  "action_type": "draft_email",
  "confidence": 0.8,
  "reasoning": "why",
  "draft": "proposed content"
}
```

Source-specific rules:
- Gmail keeps only items whose parsed sender domain matches the allow-list.
- Jira notification emails keep `mentioned_me`, `assigned_to_me`, requested
  review, comment, or status-change events directed at Leon.
- Shortcut notification emails keep `mentioned_me`, `assigned_to_me`, or new
  relevant story events directed at Leon.
- Google Sheets, Slack, Shortcut direct, and Atlassian/Jira direct are optional
  context/retrieval sources, not v1 sweep sources.
- Vault keeps existing behaviour and produces deterministic identity from the
  parsed proposal content (e.g. a stable hash) so scheduled vault sweeps do not
  blindly duplicate unchanged suggestions.

**Dedupe is pure + tested.** Before insert, reject a proposal when:

1. **Exact event:** an existing recommendation has the same `(source, sourceEventID)`
   — regardless of decision/execution state (you already saw this event).
2. **Un-triaged duplicate:** an existing `pending` recommendation has the same
   `(source, sourceItemID, actionType)`.

Rule 2 is scoped to `pending` only, so a genuinely new event on an item you have
already decided still surfaces via rule 1 (it carries a new `sourceEventID`).
Dedupe also runs within the sweep batch: two proposals for one event in a single
sweep collapse to one card.

**`SourceConfig` + `SourceState` (settings, Codable JSON in UserDefaults for now):**
```
sources: [
  { id: "gmail",    enabled: true, intervalHours: 0.5, lookbackHours: 24, overlapHours: 2,
    workingDirectory: "<vaultPath>",
    clientDomains: ["tmr.qld.gov.au", "thalesgroup.com", "codeheroes.com.au"],
    notificationSystems: ["jira", "shortcut"] },
  { id: "vault",    enabled: true, intervalHours: 24.0, workingDirectory: "<vaultPath>" }
]

sourceState: [
  { id: "gmail", lastSweptAt: "...", cursor: "...", lastSeenOccurredAt: "..." }
]
```

- `lastSweptAt` is **scheduling state**: when this source last completed a sweep.
- `cursor` / `lastSeenOccurredAt` is **ingestion state**: what external events
  were successfully scanned.
- They are separate on purpose. A failed sweep must not advance ingestion.
- Query windows use `max(cursor - overlapHours, now - lookbackHours)`. Re-seeing
  recent events is expected; dedupe absorbs repeats.
- On a successful sweep, advance `lastSeenOccurredAt` to the newest valid parsed
  event from that source, even when dedupe rejects it as already-seen. Missing or
  invalid event identity never advances ingestion state.
- Migrate current `@AppStorage("vaultPath")`, `sweepIntervalHours`, and
  `lastSweptAt` into the new vault source defaults without losing manual sweep
  behaviour.

**`SweepScheduler` → per-source.** `isDue(lastSweptAt:intervalHours:now:)` stays the
pure primitive; source state owns per-source `lastSweptAt`. The 60s app loop in
`MustardApp` checks each enabled source.

**One insert pipeline.** Both manual and scheduled sweeps share
parse → filter → dedupe → stamp → insert; there are never two divergent insert
paths. `AgentService.sweep(vaultPath:)` stays as the manual entry point — it just
skips the `isDue` gate — so command-bar/console call sites keep working and manual
vault sweeps become idempotent too. Add
`sweepDueSources(config:stateStore:now:)`, which iterates **enabled + due** sources **serially**
(one `claude -p` at a time — preserves the subscription-friendly invariant),
runs each source's prompt in `config.workingDirectory`, normalises every non-
duplicate proposal into a `Recommendation` (stamping identity + source fields),
advances that source's ingestion state only after successful parse/filter/dedupe,
then runs `applyTrust` once at the end.

**Execution cwd:** every inserted recommendation must carry a non-empty
`vaultPath`, using the source `workingDirectory`. Existing `AgentService.execute`
continues to run in `rec.vaultPath`.

**UI:** minimal. Add source settings to the Agent console rather than a large
preferences overhaul: Gmail sweep enable + interval, Gmail domain allow-list,
Jira/Shortcut notification toggles, optional context-source status, and a source
status line showing last sweep. The console already shows `source`. No new review
UI (Plan 6 already built it).

## Tasks (TDD where logic)

0. **Verify headless Gmail access** for client emails plus Jira/Shortcut
   notification emails. Google Sheets, Slack, Shortcut direct, and Atlassian/Jira
   direct are optional context sources and not required for v1 sweep discovery.
   Extend `ClaudeRunner` with `--mcp-config`/`--allowedTools` only if needed
   (+test against stub binary).
1. **Source identity types**: `SourceID`, `SourceMethod`, `SourceProposal`, shared
   date/schema parser helpers; reshape `VaultSweep` to conform (+test: vault
   prompt/parser unchanged, proposals map to stable source identity).
2. **Recommendation provenance fields**: add `sourceItemID`, `sourceEventID`,
   `occurredAt` (+model tests and in-memory SwiftData round-trip).
3. **Source config/state store**: `SourceConfig`, `SourceState`, defaults,
   migration from `vaultPath`/`sweepIntervalHours`/`lastSweptAt`, load/save
   (+tests: defaults, round-trip, migration, source-specific defaults).
4. **Dedupe engine**: pure function that decides insert/reject from existing
   recommendations (+tests: same event rejected, same non-terminal item/action
   rejected, new event allowed, terminal old item does not block new event).
5. **Thin-scout routine + `InboxIngest`** (per ADR-0007 / thin-scout spec): the
   routine prompt (Gmail discovery + vault grounding + `_inbox/` write) and the
   Mac-side `InboxIngest` — `git pull`, parse/validate inbox files,
   `isClient(sender:allowList:)` enforced Mac-side, dedupe, insert pending
   (+tests: allow-list match incl. codeheroes/sub-domains/case-insensitive,
   non-client rejected, Jira/Shortcut filters, malformed/missing-identity file
   rejected, source/url stamped, dedupe across pull cycles).
6. **Retrieval-grounded execution prompt** (Mac, still needed): final drafts re-read
   the candidate's source context and search vault/ticket context when identifiers
   are present (+tests: email draft prompt includes retrieval instructions,
   feedback remains incorporated, no send/file instructions).
7. **Per-source scheduling + `AgentService.sweepDueSources`**: serial iteration,
   cwd from source config, parser/filter/dedupe/insert, cursor-safe state advance,
   one `applyTrust` call at the end (+tests with stubbed `ClaudeRun`).
8. **Unify the insert pipeline**: route both `sweep(vaultPath:)` (manual) and
   `sweepDueSources` through one parse → filter → dedupe → stamp → insert path —
   manual just skips the `isDue` gate. Command-bar/console call sites keep working
   (+tests: manual vault sweep dedupes too; build coverage for call sites).
9. **`MustardApp` loop + Agent settings UI**: the 60s loop runs due local sources
   and an `InboxIngest` `git pull`; settings expose the vault Git repo, scout status
   (last ingest, last error), allow-list, and per-source enable/interval. (No Gmail
   OAuth settings — discovery is the routine's.) Build / relaunch / commit.

## Done when

- `swift test` green; vault sweep behaviour unchanged.
- Re-running the same source sweep multiple times does not duplicate existing
  non-terminal cards for the same external event.
- Enabling Gmail surfaces only allow-listed-domain emails as pending cards with
  source = `gmail`, source identity, context, and a working `sourceURL`.
- Jira and Shortcut activity surfaces from Gmail notifications, with stable source
  identity.
- Recommendations and final drafts are grounded in the email/thread plus bounded
  vault context, and optionally ticket context when available.
- Each source sweeps on its own interval; runs stay serial (one `claude` at a time).
- Failed source runs do not advance ingestion cursor/state.
- No downstream review/trust/output behaviour changed.
