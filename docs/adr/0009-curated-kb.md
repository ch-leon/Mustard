# ADR-0009 — Curated KB: store only what's Kept; retire the email→KB firehose

**Status:** Accepted (2026-06-19). **Builds on ADR-0008.**

## Context
ADR-0008 made the email scout local-only: a local routine writes grounded `gmail` rec
JSON into `<project>/_recs/`, which Mustard ingests via `InboxIngest`. But email was also
reaching the knowledge base by a *second*, separate path — an external email→KB-note
"firehose" routine that wrote a note per email into the vault. That meant the same email
could surface twice (as a `gmail` rec **and** as a vault note that the next sweep
re-proposes), the KB filled with machine-written notes nobody chose to keep, and email
provenance was laundered into `VAULT`. The triage spec
`docs/specs/2026-06-19-triage-provenance-fyi-and-fanout-design.md` resolved this by
locking a single model for what the KB is *for*.

## Decision
The KB is **curated** — it stores only what Leon explicitly **Keeps**:
- The external email→KB firehose is **retired** (operational, Leon's side). Email reaches
  Mustard **only** as first-class `gmail` recommendations via the scout's `_recs/`
  (`InboxIngest` on the ~10-min app loop) — the path ADR-0008 already established.
- **Keep** is the only way an item's content enters the KB. `AgentService.keep(_:)` appends
  a markdown entry to a single rolling log at **`<project>/_filed/inbox-log.md`**, then
  marks the rec terminal. The entry and path are pure, unit-tested code in
  `Logic/InboxLog.swift` (`entry(...)` formats, `logURL(workingDirectory:)` places). No
  `claude -p`, no `OutputCard` — filing is a direct local write.
- The vault sweep now **ignores app-internal folders** so filed/ingested files never loop
  back as proposals: `VaultSweep.prompt` tells the model to skip `_filed/` (the Keep log),
  `_recs/` (the scout's drop folder), and `.obsidian/`.

## Consequences
- One inbound email path and one curation gesture: the KB holds intentional, Kept content
  instead of an unfiltered firehose, and email keeps its `gmail` provenance through triage.
- The `_filed/` subfolder + sweep-ignore line are **load-bearing together** — without the
  ignore, a Kept note would be re-proposed on the next sweep (an infinite loop). The ignore
  set must stay in `VaultSweep.prompt`.
- "Firehose off" is an **operational** prerequisite (Leon disables the routine), not code —
  until it is off, emails can still double up as vault notes.
- A rolling log (not one-note-per-item) keeps Kept items durable and greppable without
  scattering files. Durability for grouped recs is covered by Keep, so the persisted
  `SourceItem` entity stays deferred (Option B in the spec).
- Reversible/contained: nothing in SwiftData changes, and re-enabling a KB-writing routine
  would only mean writing under an ignored folder (or re-admitting it as a sweep source).
