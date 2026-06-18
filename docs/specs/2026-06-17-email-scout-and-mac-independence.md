# Email scout + Mac-independence — future direction (DEFERRED)

**Status:** Email scout = **BUILT, local-only** (see **ADR-0008**) — the cloud-routine
specifics below are superseded by the local model. **Mac-independence** (act from phone
with the Mac off) = still **deferred**; that part of this doc stands.
**Date:** 2026-06-17
**Related:** ADR-0007 (cloud scout for email), ADR-0003 (Mac-anchored subscription
agent), ADR-0001 (SwiftData + CloudKit, no backend), `2026-06-15-thin-cloud-scout.md`.

## Why this note exists
Across the multi-source-sweep work we designed how to (a) add **email** as a source and
(b) progressively reduce the Mac dependency toward a real **mobile** experience. We are
not building that yet — this preserves the thinking so we can resume cleanly.

## Where things are now (built this phase)
- Source-agnostic foundation: `SourceProposal`/`SourceID`, pure dedupe, provenance,
  per-source config/state, unified insert pipeline, `sweepDueSources`.
- **Multi-project isolation** (tested): project-qualified identity (hash + dedupe),
  per-KB `workingDirectory` (cwd-isolated), `Recommendation.project`.
- App loop runs `sweepDueSources`; per-project **Projects** panel in the Agent console.
- KBs now live in **private GitHub repos** — `BiggestFella/DLKB`, `SBKB`, `SANKB`
  (verified private + secret-free), each a Tolaria vault (standard git, honors `.gitignore`).
- **No email yet, no cloud routine running** — everything is Mac-local vault sweeps.

## The constraint that shapes everything
Local headless `claude -p` (scrubbed env) **cannot reach Gmail** (ADR-0007, proven). So
*any* email ingestion needs a **cloud routine** (which gets the Gmail connector). A
Claude Code routine: reads Gmail ✅, pushes to a private repo ✅, includes 25
runs/rolling-24h on the Team plan (Leon expects ~2–3/day, well under).

## Scout designs (when we resume)
**A — Mac-grounds (lightest off-Mac step).** One routine captures Gmail → writes raw
candidates to a small `mustard-inbox` repo. The Mac grounds them against the **live local
KB**, dedupes, inserts. Simple routine (no KB access); grounding is freshest.

**B — Cloud-grounds, one routine per KB (Leon's preferred shape).** Each KB has its own
self-contained routine: filter Gmail to that client's domains → ground against its **own
attached repo** → write grounded recs to a `_recs/` folder in that repo. No cross-repo
cloning (each routine = one repo), full per-project isolation, budget fine at 2–3/day
each. Caveat: grounds against the KB **as last synced** (Tolaria push), not the live copy.

Either way, the Mac **ingests** the rec files into SwiftData via a Mac-side `InboxIngest`
(pull → validate → per-project allow-list → dedupe → insert).

## Execution (stays Mac-bound)
Execution runs `claude -p` on the Mac (ADR-0003), so it always needs the Mac on. To
support **approve anywhere (incl. phone), execute when the Mac next wakes**, add a small
**catch-up pass**: the loop runs any rec that is `approved` but `executionState == idle`.
(Today `approve` executes immediately and only on the Mac.)

## Mobile
Today's ADRs already design mobile as **iOS observing the SwiftData store via CloudKit**
("iOS never runs the agent"). That works with the Mac-on model: the Mac creates recs →
CloudKit → phone sees/triages them (even when the Mac is later off); only *new rec
creation* and *execution* need the Mac. Grounding location (Mac vs cloud) does not change
this — the Mac is always the bridge into SwiftData, which CloudKit syncs.

## What full Mac-independence ("act from phone, Mac off") would take
A real pivot, each piece with a cost:
1. **Cloud execution** — run actions in routines, not on the Mac → re-introduces
   **metered billing** (rewrites ADR-0003's subscription economics).
2. **Repo/vault-as-source-of-truth** — recs live in repos the phone reads directly,
   not SwiftData (rewrites ADR-0001's SwiftData-as-truth + CloudKit-observe model).
3. **Mobile reads the repo** (git/API on iOS) instead of CloudKit-observe.

Design B's per-KB routines are step 1 (of *grounding*); full independence also needs
cloud *execution* + a repo-reading mobile client.

## The Mac-side build ready to pick up (unblocked, TDD)
- `InboxIngest`: consume `_recs/`/inbox files → validate → allow-list → dedupe → insert
  (reads files, no live remote needed).
- Make `SourceProposal` `Codable` (the rec/candidate JSON format).
- The per-KB routine prompt (authored text to paste into each routine).
- Deferred-execution catch-up in the loop.
- (Design A only) a `mustard-inbox` repo — not needed for Design B (recs go in each KB repo).

## Decision
**Deferred.** This phase stays **Mac-on / Mac-local** — local vault sweeps only, no cloud
routine, no email. Revisit when *always-on email capture* or *act-from-phone-with-Mac-off*
becomes a priority; resume from "The Mac-side build ready to pick up" above.
