# Source labelling, Ignore-bucket vanish, and ticket/task bucketing — design

**Date:** 2026-06-24
**Status:** Proposed (awaiting Leon's spec review)
**Branch:** `feat/source-labels-and-ignore-rules`

## Context

All Jira/Shortcut updates currently reach Mustard through the **local Gmail scout
routine** ([scout-routine-prompt.md](../scout-routine-prompt.md)), which writes
`_recs/*.json` that the app ingests every ~10 min. Three things follow from that and
from reviewing live cards in the Agent console:

1. Every Jira/Shortcut card is badged **"Gmail"** (the transport), even though the
   meaningful source is Jira or Shortcut. The "Jira · DLA-5280 …" text is only the
   free-form `sourceContext` shown next to the Gmail pill.
2. **PO Review** sub-tasks assigned to Leon in Shortcut are routine and shouldn't
   need triage — but they currently land as actionable cards.
3. An `ignore`-bucketed rec still renders the full Approve/Reject row, and approving
   it fires a pointless `claude` run (it isn't `fyi` or `create_task`, so it falls
   through to `execute()`). Re-bucketing a card to **Ignore** therefore doesn't make
   it go away.
4. The classifier sometimes buckets "check this *existing* ticket's status" mentions
   as `ticket_write` (which means *draft a new ticket*) when they should be
   `create_task`.

## Goals

1. Badge Jira/Shortcut-derived recs with a **Jira (blue)** or **Shortcut (purple)**
   source pill, replacing the Gmail pill. The email stays reachable via "Open ↗".
2. Auto-bucket Shortcut **"PO Review"** assignments as `ignore`, and make **all**
   `ignore` recs **vanish from the triage queue** (whether auto-set or hand-picked).
3. Refine the classifier prompts so "check / verify / reply about an existing ticket"
   routes to `create_task`, not `ticket_write`.

## Decisions (brainstorming, 2026-06-24)

- **Source pill:** replace Gmail with Jira/Shortcut. Jira = blue, Shortcut = purple.
- **Ignore:** vanish from the queue.
- **Bucketing fix:** prompt refinement (judgment-based; **not** unit-tested; Leon
  must re-paste the scout prompt into his local routine for Gmail cards to benefit).
- **Transition duplicate:** accepted, **no migration** (see Transition note).

## Non-goals (YAGNI)

- No new source *transports* — the Gmail scout remains the delivery path; we only
  re-label the logical source Mac-side.
- No Mac-side deterministic guard for goal 3 (prompt-only, by decision).
- No migration of already-stored `gmail` rows.
- No change to dedupe/grouping *semantics* beyond what source reclassification implies.

## Architecture

Every deterministic rule lands as a **pure unit in `Logic/`** and is applied in the
**shared `ingest()` pipeline** ([AgentService.swift:111](../../Sources/MustardKit/Agent/AgentService.swift))
so it covers manual sweeps, scheduled sweeps, and inbox ingest uniformly. Views only
render and dispatch (the queue filter is extracted into a pure helper so it, too, is
testable).

**Ingest data flow (new step in bold):**

```
scout _recs/*.json  ─┐
                     ├─► [SourceProposal] ─► IngestNormalizer.normalize ─► SourceDedupe ─► Recommendation(from:) ─► insert
vault sweep parse  ─┘                         (reclassify source +
                                               PO-review → ignore)
                                                                          queue view ─► RecommendationQueue.pending (drops ignore) ─► SourceGrouping ─► rows
```

`IngestNormalizer` runs **before** dedupe so the deterministic, repeatable source
value is what dedupe keys on.

---

## Feature 1 — Source labelling (Jira/Shortcut pill)

**Model — `Agent/SourceProposal.swift`**
- `SourceID` gains `case jira` and `case shortcut`.
- Add a copy helper so the (immutable) struct can be re-stamped during normalization:
  `func reclassified(source: SourceID, actionType: String) -> SourceProposal`.

**Badge — `Logic/SourceBadge.swift`** (stays pure — no SwiftUI import)
- Add `fgHex: String` and `bgHex: String` to `SourceBadge` (empty for quiet/vault).
- New badges:
  - `.jira` → symbol `diamond.fill`, label "Jira", `isQuiet: false`, blue
    (`fg #2E5CB8`, `bg #E7EEF9`) — distinct from the accent blue `#2D7FF9`.
  - `.shortcut` → symbol `flag.fill`, label "Shortcut", `isQuiet: false`, purple
    (`fg #5B4AA8`, `bg #ECE8F7`).
  - `.gmail`/`.vault` unchanged (gmail carries its existing red `#A32D2D`/`#FCEBEB`).

**Classifier — `Logic/SourceClassifier.swift` (new, pure)**
- `static func logicalSource(transport: SourceID, sourceContext: String) -> SourceID`
- Rules (only `gmail` is ever reclassified — vault/delegated pass through):
  1. `transport != .gmail` → return `transport`.
  2. Leading segment of `sourceContext` (text before the first `·`, trimmed,
     case-insensitive) is `jira` → `.jira`; `shortcut` → `.shortcut`.
  3. Else if `sourceContext` contains a Jira-style key `[A-Z]{2,}-\d+` → `.jira`.
  4. Else → `.gmail` (unchanged).

**View — `Views/AgentConsoleView.swift` (`ProvenancePill`)**
- In the **non-quiet** (pill) branch, replace the hardcoded red colours with
  `badge.fgHex` / `badge.bgHex` (via `Color(hex:)`). The quiet branch (vault) is
  unchanged. No layout change; `sourceURL`'s "Open ↗" still opens the Gmail thread.

**Wiring — `Agent/AgentService.swift`**
- `ingest()` maps each proposal through `IngestNormalizer.normalize` (Feature 2 owns
  the function; source reclassification is its first step).

**Tests**
- `SourceClassifierTests` (new): "Jira · DLA-5280 · …" → jira; "Shortcut · Digital
  Licence · …" → shortcut; key-only context ("…mentioned on DLA-5280") → jira;
  unknown gmail context → gmail; vault → vault; delegated → delegated.
- `SourceBadgeTests` (extend): jira/shortcut label, symbol, colours; `forRaw` round-trip.

---

## Feature 2 — Ignore vanishes (incl. PO Review)

**Normalizer — `Logic/IngestNormalizer.swift` (new, pure)**
- `static func normalize(_ p: SourceProposal) -> SourceProposal`:
  1. `let src = SourceClassifier.logicalSource(transport: p.source, sourceContext: p.sourceContext)`
  2. `let action = demotesToIgnore(source: src, title: p.title, sourceContext: p.sourceContext) ? "ignore" : p.actionType`
  3. return `p.reclassified(source: src, actionType: action)`
- `static func demotesToIgnore(source:title:sourceContext:) -> Bool`:
  true when `source == .shortcut` **and** "po review" appears (case-insensitive) in
  `title` or `sourceContext`. Scoped to Shortcut — matches the assignment notifications.

**Queue helper — `Logic/RecommendationQueue.swift` (new, pure)**
- `static func pending(_ recs: [Recommendation], now: Date) -> [Recommendation]`:
  `decision == .pending` **and** not snoozed (`snoozedUntil == nil || <= now`)
  **and** `action != .ignore`.
- `AgentConsoleView.pending` ([AgentConsoleView.swift:20](../../Sources/MustardKit/Views/AgentConsoleView.swift))
  delegates to this helper (removes the inline filter). Makes the ignore + snooze
  rule unit-testable and keeps the view dumb.

**Trust — `Agent/AgentService.swift`**
- `applyTrust` skip ([AgentService.swift:134](../../Sources/MustardKit/Agent/AgentService.swift))
  becomes `if rec.action == .fyi || rec.action == .ignore { continue }` so ignore
  items are never auto-executed.

**Behaviour notes**
- Auto-ignored PO reviews and any card you hand-set to **Ignore** both disappear from
  the queue immediately (one filter, both paths). This resolves the earlier Card 3
  question: re-bucketing to Ignore now *removes* the card — there is no Approve step.
- Ignore recs are still *inserted* (so dedupe stays stable and there's an audit trail);
  they're simply filtered out of the queue and never auto-run.

**Tests**
- `IngestNormalizerTests` (new): shortcut + "PO Review" in title → ignore; in context
  → ignore; shortcut without it → action unchanged; jira/gmail with "PO Review" →
  unchanged (scoped to shortcut); composes with source reclassification.
- `RecommendationQueueTests` (new): excludes ignore; excludes future-snoozed; keeps
  due/pending; keeps fyi.
- `AgentTests` (extend): a pending `ignore` rec under Trusted + high confidence is
  **not** executed (claude stub uncalled, no OutputCard).

---

## Feature 3 — ticket_write vs create_task (prompt refinement)

**`Agent/VaultSweep.swift` — `prompt`** ([VaultSweep.swift:19](../../Sources/MustardKit/Agent/VaultSweep.swift)):
add to the `Rules:` block:

> - Ticket vs task: `ticket_write` means DRAFTING A NEW ticket/story. If an item asks
>   you to check, verify, confirm, review, or reply about an EXISTING ticket, use
>   `create_task` (a to-do to action it) or a draft reply — never `ticket_write`.

**`docs/scout-routine-prompt.md`** — add the same clause to the action-token guidance
(the `GROUND + WRITE` section).

**Verification:** judgment-based, **no automated test**. Confirmed by observing the
next sweeps/scout runs. **Leon re-pastes the scout prompt into his local routine** for
Gmail cards to pick it up.

---

## Transition note (accepted)

`SourceDedupe.shouldInsert` keys on `(source, sourceEventID)`
([SourceDedupe.swift:14](../../Sources/MustardKit/Logic/SourceDedupe.swift)). Any
Jira/Shortcut email **already** stored as `gmail` won't match the new `jira`/`shortcut`
identity, so it may surface **once** more before settling. Low volume, self-correcting,
no migration — accepted in brainstorming.

## Files touched

| File | Change |
|------|--------|
| `Agent/SourceProposal.swift` | `SourceID` += jira, shortcut; `reclassified(source:actionType:)` helper |
| `Logic/SourceBadge.swift` | `fgHex`/`bgHex`; jira + shortcut badges |
| `Logic/SourceClassifier.swift` | **new** — transport + context → logical source |
| `Logic/IngestNormalizer.swift` | **new** — compose source reclassify + PO-review→ignore |
| `Logic/RecommendationQueue.swift` | **new** — pure pending filter (drops ignore) |
| `Agent/AgentService.swift` | `ingest()` normalizes; `applyTrust` skips ignore |
| `Views/AgentConsoleView.swift` | `pending` uses helper; `ProvenancePill` uses badge colours |
| `Agent/VaultSweep.swift` | prompt: ticket_write vs create_task rule |
| `docs/scout-routine-prompt.md` | same rule for the Gmail scout |

## Testing recap

TDD (failing test first) for all pure units: `SourceClassifierTests`,
`IngestNormalizerTests`, `RecommendationQueueTests` (new); `SourceBadgeTests`,
`AgentTests` (extend). `swift build` green; Leon eyeballs the pills (agent can't
screenshot the native app).

## Open follow-up (verify during planning, not committed here)

Other surfaces that count "pending" recs (notch / hover / command bar) may want to
route through `RecommendationQueue.pending` too, so ignore items don't inflate a
"needs you" count. Audit during plan; fold in only if cheap and consistent.
