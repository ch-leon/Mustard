# ADR-0007 — Email discovery via a cloud-routine "thin scout", not the local CLI

**Status:** Accepted (2026-06-15)

## Context
Multi-source sweep needs email. Two facts settled the transport:

1. Mustard's local agent (`ClaudeRunner`: `claude -p`, scrubbed env, closed stdin)
   **cannot reach Gmail.** A faithful probe returned `NONE`: the Gmail/Slack/Calendar
   entries in `claude mcp list` are **claude.ai account connectors**, not local CLI
   MCP servers, and a standalone app lacks the session OAuth context they need. So
   the ADR-0003 Mac-anchoring has no email path without Mustard building its own OAuth.
2. A **Claude Code routine** *can*: verified 2026-06-15 — a scheduled routine read
   Gmail via the connector (55 threads/24h) and pushed to a private repo
   (BiggestFella/Mustard, PR #7). Routines include **25 runs/rolling-24h** free; at
   ≤25/day (hourly = 24) there is no metered billing, so ADR-0003's economics hold.

Options: **(A)** Mustard-owned Gmail OAuth — Mac-anchored, a build cost, only sweeps
while the Mac is awake; **(B)** a cloud routine — also closes a gap CloudKit-observe
cannot: discovery while the Mac is asleep.

## Decision
Adopt the **thin cloud scout** (design: `docs/specs/2026-06-15-thin-cloud-scout.md`):

- An hourly routine discovers client + Jira/Shortcut-notification emails via the
  Gmail connector, grounds them against the vault (it runs in a clone of the vault
  repo), and writes candidate `SourceProposal`s as files into a Git-synced vault
  `_inbox/`.
- The routine is the **sole writer**; the Mac is **read-only** (`git pull`) and
  ingests via a new `InboxIngest` into SwiftData using the existing dedupe.
- **SwiftData stays the source of truth — ADR-0001 unchanged. Execution stays on
  the Mac — ADR-0003 unchanged for execution.** Cadence ≤25 runs/24h.
- This **drops the Mustard-owned Gmail OAuth build** and supersedes the plan's
  earlier assumption that the local CLI would search Gmail.

## Consequences
- Always-on email *discovery* independent of the Mac's power state; no OAuth build;
  Gmail via the connector the routine gets for free.
- New requirement: the vault lives in a **private GitHub repo**; the Mac needs
  `git pull` on it. The vault repo becomes a discovery transport — the single-writer
  contract is load-bearing (keeps it git-conflict-free).
- Privacy: the routine reads Gmail in Anthropic's cloud and pushes model-summarized
  candidate files (titles/drafts, no raw bodies per the prompt) to a private repo.
  Acceptable for personal use; noted.
- Trust/auto-run can now act on email-derived candidates. Email/Slack/ticket stay
  always-gated (ADR-0006), but non-gated email-derived actions
  (`create_task`/`vault_note`/`fyi`) can auto-run under Trusted+ — a real widening of
  the autonomy surface to keep in mind.
- Subscription economics hold only while cadence ≤25/day; aggressive cadences meter
  (opt-in).
- Mobile remains **CloudKit-observe** (ADR-0001/0004). True Mac-independent mobile
  (vault-as-source-of-truth) is deliberately deferred.
- Reversible: if routine Gmail access regresses (bug #37789), fall back to (A)
  Mac-anchored OAuth — the `SourceProposal`/dedupe/provenance foundation is shared
  and unaffected.
