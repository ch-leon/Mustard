# ADR-0008 — Email scout is local-only (no cloud routines, no git)

**Status:** Accepted (2026-06-17). **Supersedes ADR-0007.**

## Context
ADR-0007 chose a cloud Claude Code routine to read Gmail, because the local headless
`claude -p` (scrubbed env) can't reach the Gmail connector. Building it surfaced real
costs: a git sync path for the KBs (with the secret-leak scare and the 769 MB mess),
drift between the pushed snapshot and the live KB, per-repo routine setup, and reliance
on the cloud. Leon then committed to a **fully local, Mac-on** phase and confirmed a
**local** routine (Claude desktop local-agent / local scheduled task) *can* reach Gmail.
With that, the cloud routine + git add no benefit.

## Decision
The email scout is **local-only**:
- **One local routine** (Gmail + filesystem) reads Gmail, routes each email to the right
  project by client domain, grounds against that project's **local** KB folder, and writes
  grounded rec JSON into `<project>/_recs/` — directly, no git.
- **Mustard ingests** each project's local `_recs/` via `InboxIngest` (decode →
  per-project dedupe → insert) on its ~10-minute loop. Files are local and immediate.
- The `SourceProposal`/dedupe/provenance foundation and per-project isolation are reused
  unchanged. `GitRunner` and all push/pull are removed.
- One routine covers all projects; project-qualified identity keeps them isolated.
- The KB GitHub repos (DLKB/SBKB/SANKB) remain only as Leon's Tolaria sync/backup — the
  scout does not use them. Prompt: `docs/scout-routine-prompt.md`.

## Consequences
- Simplest path: no cloud billing, no git sync, no secret-leak surface; grounding is
  against the live local KB.
- Requires the Mac on (capture + ingest + execute are all local) — accepted this phase.
- **Deferred (unchanged):** Mac-independence / act-from-phone-with-the-Mac-off — still the
  bigger pivot in `2026-06-17-email-scout-and-mac-independence.md` (cloud execution +
  repo-as-truth). Not this phase.
- `2026-06-15-thin-cloud-scout.md` is retained as historical context only.
