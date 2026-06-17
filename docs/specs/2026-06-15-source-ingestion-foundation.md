# Source Ingestion Foundation Design

**Status:** Draft for review  
**Plan:** `docs/plans/2026-06-15-multi-source-sweep.md`  
**Goal:** Let Mustard sweep email many times per day while producing stable,
deduped, context-grounded `Recommendation` cards in the existing review queue.

## Problem

The current agent loop has one source: the Obsidian vault. Scheduled sweeps can ask the CLI for recommendations and insert them into SwiftData, but the system does not yet have a durable concept of an external source event.

Gmail is the v1 discovery source. It contains direct client emails plus Jira and
Shortcut notification emails. Email can return the same item repeatedly across
searches, lookback windows, retries, and scheduled runs. If Mustard only trusts
prompt text, the user will see duplicate cards for the same email thread or
notification. Because sweeps are expected to run multiple times per day, source
identity and dedupe are product requirements, not cleanup tasks.

## Source Availability

> **Superseded for Gmail (ADR-0007).** The local headless `claude -p` was proven
> unable to reach the Gmail connector; Gmail discovery is now delivered by the
> thin-scout cloud routine (`2026-06-15-thin-cloud-scout.md`), which writes candidate
> proposals into a Git-synced vault `_inbox/` that the Mac ingests via `InboxIngest`.
> The CLI-search framing below is retained for the **vault** source and as historical
> context.

Mustard does not own direct Gmail, Shortcut, Slack, Google Sheets, or Jira API
integrations in this design. Source agents ask the headless CLI to use whatever
tools are configured for that local CLI session.

Jira and Shortcut are not direct sweep sources in v1. Their activity is discovered
through notification emails. Leon does not yet have an Atlassian MCP/API
connection, and Shortcut is currently a local-dev connector visible in the desktop
UI but not in the headless Claude CLI MCP list.

Jira ticket information may still be useful as context. It can come from:

- Jira notification emails in Gmail
- a Google Sheet populated by a client-side extension
- Jira Slack notifications in Slack
- a future Atlassian connector

The v1 sweep should therefore be modeled as an **email-led intake** with optional
context retrieval, not as separate Jira/Shortcut/Slack/Sheets sweep sources.

Before implementing source-specific prompts, Task 0 must prove availability:

- Gmail: headless CLI can search/read the mailbox source needed for allow-listed senders and Jira notifications.
- Optional context sources: Google Sheets, Slack, Shortcut, and Atlassian direct
  stay disabled for sweep discovery until they are available to the same headless
  runner Mustard uses.

If a context source cannot be proven, it stays disabled and the recommendation
must say which context could not be checked. In the current Codex session,
Shortcut MCP tools are visible, but Shortcut was not visible to `claude mcp list`;
it should remain conditional until the local-dev connector is made available to
the same headless runner Mustard uses.

## Core Contracts

Every source agent emits `SourceProposal` values. A proposal is not just a recommendation draft; it is a recommendation plus provenance.

```swift
public enum SourceID: String, Codable, CaseIterable {
    case gmail
    case vault
}

public struct SourceProposal: Equatable {
    public let source: SourceID
    public let sourceItemID: String
    public let sourceEventID: String
    public let sourceContext: String
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

`sourceItemID` identifies the durable parent object, such as a Gmail thread or
vault-derived hash. `sourceEventID` identifies the triggering event, such as a
Gmail message id or deterministic vault proposal hash.

Parsers reject proposals that do not include enough identity to dedupe. They also
clamp confidence, normalize source ids, parse dates, and reject malformed URLs
rather than inserting fuzzy cards.

## Context-Grounded Recommendations

Every recommendation should be thought out, not merely a thin restatement of an
email. The email sweep has two passes:

1. **Candidate discovery:** find recent relevant client emails plus Jira/Shortcut
   notification emails.
2. **Bounded context gathering:** before emitting a recommendation, inspect the
   email thread plus relevant local knowledge-base context. If the email contains
   a defect id, ticket key, project name, or client keyword, search the vault for
   matching notes. Optional context sources such as a ticket spreadsheet, Slack,
   Shortcut, or Atlassian may be queried only when they are available and the
   candidate contains a specific identifier worth checking.

The resulting `Recommendation.reasoning` should mention the evidence used at a
high level, such as "email thread + vault note about DEF-123", without dumping
private content into the UI.

For gated actions such as email replies, the sweep may include a preview draft,
but approved execution must perform retrieval again before producing the final
`OutputCard`. The final draft should be grounded in:

- the source email/thread
- relevant vault notes
- available ticket context when a ticket/defect id is present
- user feedback added during review

Mustard still never sends email or files ticket updates automatically.

## Recommendation Provenance

`Recommendation` gains three fields:

```swift
public var sourceItemID: String?
public var sourceEventID: String?
public var occurredAt: Date?
```

Existing fields stay in place:

- `source`
- `sourceContext`
- `sourceURL`
- `confidence`
- `reasoning`
- `draft`
- `vaultPath`

**Notification system (Jira vs. Shortcut vs. direct client).** Gmail folds three
flavours under `source = gmail`. The `notification_system` value the prompt returns
is used by the parser for filtering; for v1 it is **not** promoted to its own
queryable column — it is woven into the human-readable `sourceContext`
(e.g. `Jira · PROJ-123 · new comment from Alice`). Only **dedupe identity**
(`sourceItemID`, `sourceEventID`) must stay structured and is never packed into
`sourceContext`; non-identity provenance like the notification system may live
there. Promote it to a real field only if/when filtering cards by notification
system becomes a feature — not before.

Every inserted recommendation must carry a non-empty `vaultPath`, using the source's configured working directory. Existing execution behavior can continue to run in `rec.vaultPath`.

## Parser-Enforced Filtering

Prompt filtering is helpful but not sufficient. Each source must surface raw metadata, and each parser must enforce the final allow/deny decision. For Gmail, "the parser" now runs **Mac-side in `InboxIngest`** over the routine's `_inbox/` files (ADR-0007) — the required fields and allow/deny rules below are unchanged; only the producer moved from a local CLI prompt to the cloud routine.

Gmail requires:

- `source_item_id`
- `source_event_id`
- `sender_email`
- `sender_domain`
- `received_at`
- `source_url`

Gmail keeps only messages whose sender domain matches the configured allow-list. Domain matching is case-insensitive and subdomain-aware, so `alerts.sub.client.com` matches `client.com`.

Jira and Shortcut notification emails require the same Gmail identity fields plus:

- `notification_system`: `jira` or `shortcut`
- `ticket_key` or `story_id` when present
- `event_type`
- `mentioned_me`
- `assigned_to_me`

Jira/Shortcut notifications keep messages that indicate assignment, mention,
requested review, status changes, comments directed at Leon, or new relevant
tickets/stories.

Google Sheets, Slack, Shortcut direct, and Atlassian/Jira direct are optional
retrieval/context sources in v1, not sweep discovery sources. If any of them
becomes a sweep source later, it should conform to the same `SourceProposal`
contract.

Vault keeps existing behavior, but maps parsed proposals into deterministic source identity so repeated scheduled vault sweeps do not blindly duplicate unchanged suggestions.

## Dedupe Rules

Dedupe is a pure function over a `SourceProposal`, the set of existing
`Recommendation` records, and the proposals already accepted earlier in the same
sweep batch.

Reject a proposal when:

1. **Exact event already seen.** An existing recommendation has the same
   `(source, sourceEventID)` — regardless of its decision or execution state.
   The user has already seen this exact external event, so it never re-surfaces.
2. **Un-triaged duplicate of the same item + action.** An existing recommendation
   with `decision == pending` has the same `(source, sourceItemID, actionType)`.
   This collapses the case where one thread/item yields several near-identical
   candidates before any of them has been triaged.

Rule 2 is deliberately scoped to `pending` only. Once an item has been *decided*
(approved, scheduled, denied, or self-execute), a genuinely new event on the same
item — a new message on the thread, a new comment on the ticket — carries a new
`sourceEventID`, so rule 1 lets it through and the new activity surfaces. An
earlier draft listed `approved`/`scheduled`/`running` as "non-terminal" blockers
for rule 2; that was a bug, because `decision` never transitions back from
`approved`, so it would have permanently suppressed all future activity on any
thread you had ever actioned.

Within a single sweep, dedupe also runs against proposals already accepted earlier
in the same batch, so two proposals describing the same event in one sweep
collapse to a single card.

## Source State

Each source has config and state.

Config:

- `id`
- `enabled`
- `intervalHours`
- `lookbackHours`
- `overlapHours`
- `workingDirectory`
- source-specific settings such as Gmail domains, notification filters, optional
  ticket sheet id/range, optional Slack channels, or Leon's user identifiers

State:

- `lastSweptAt`
- `cursor`
- `lastSeenOccurredAt`
- optional `lastError`

`lastSweptAt` is scheduling state. `cursor` and `lastSeenOccurredAt` are ingestion state. They must not be collapsed into one field.

Query windows use:

```text
max(cursor - overlapHours, now - lookbackHours)
```

Overlap deliberately re-reads recent external events. Dedupe absorbs repeats.

On a successful sweep, advance `lastSeenOccurredAt` to the newest valid parsed event from that source, including events rejected by dedupe. Missing or invalid event identity never advances ingestion state.

Failed source runs do not advance ingestion state. They may record `lastError`.

## Sweep Flow

Scheduled sweep:

```text
load source config/state
find enabled + due sources
for each due source, serially:
  build prompt from config + state + now
  run CLI in source workingDirectory
  parse SourceProposal[]
  filter malformed/irrelevant proposals
  dedupe against existing Recommendations
  insert non-duplicates
  advance source state only after successful parse/filter/dedupe
after all due sources:
  applyTrust once
```

Both manual and scheduled sweeps insert through **one** pipeline:
parse → filter → dedupe → stamp identity → insert. There must not be two
divergent insert paths. `AgentService.sweep(vaultPath:)` stays as the manual entry
point (command bar and the Agent-console button), but is reshaped to run the vault
source through that shared pipeline, skipping only the `isDue` check. This makes
manual vault sweeps idempotent too — re-running the button no longer duplicates
unchanged vault cards, which today's direct-insert `sweep()` does not guarantee.

**Gmail is not a CLI source in this flow (ADR-0007).** Its discovery runs in the
cloud scout; the Mac's equivalent of "run + parse" for Gmail is `InboxIngest`
(`git pull` → read `_inbox/` → the same filter/dedupe/insert pipeline). The
pseudo-code's "run CLI in workingDirectory" applies to the **vault** source.

## Storage And Migration

Use a small Codable settings/state blob in `UserDefaults` for v1. This matches the current light settings style and avoids introducing a new SwiftData settings model before it is needed.

Migration reads current keys:

- `vaultPath`
- `sweepIntervalHours`
- `lastSweptAt`

Those become the default vault source config/state. Existing manual sweep buttons and command-bar sweep behavior must continue to work.

## UI

Keep UI minimal inside the Agent console:

- Gmail sweep enable toggle
- Gmail sweep interval
- Gmail domain allow-list
- notification filters for Jira and Shortcut emails
- optional context-source status for ticket sheet, Slack, Shortcut direct, and
  Atlassian direct
- source status line with last successful sweep and last error

No new review UI is required. Cards continue to use the existing recommendation and output review flow.

## Testing

Logic tests are required for:

- source proposal parsing and malformed email identity rejection
- Gmail allow-list domain matching
- Jira notification email filters
- Shortcut notification email filters
- bounded vault context retrieval prompt construction
- dedupe exact event rejection
- dedupe same item/action non-terminal rejection
- allowing new events for an old terminal item
- config/state round-trip
- migration from existing vault settings
- failed sweeps not advancing ingestion state
- successful duplicate sweeps advancing `lastSeenOccurredAt` from valid parsed events
- serial source execution with a stubbed CLI runner

Build verification remains `swift build`. View changes are verified by build and Leon's visual confirmation.

## Open Decisions

- Whether Google Sheets should be used as an optional context source during
  final drafting. It must be available to the same headless runner Mustard uses.
- Whether Slack should be used as optional context during final drafting. Gmail
  notification sweep is enough for v1 discovery.
- Whether Shortcut MCP supports useful direct context retrieval in the headless
  runner. If not, Shortcut notification emails remain the v1 path.
- Whether Atlassian/Jira direct becomes available later. It is not required for
  v1 discovery.
- Whether source state should graduate from UserDefaults to SwiftData after v1. For now, UserDefaults is enough.
- Whether to promote `notification_system` to its own queryable `sourceKind`
  column now, or keep it inside `sourceContext` until card-filtering needs it
  (v1 keeps it in `sourceContext`).
