# Thin Cloud Scout — always-on discovery via a Git-synced vault inbox

**Status:** Verified (2026-06-15) — both gate probes **PASSED** (Gmail callable
from a routine: 55 threads/24h; private-repo push OK via BiggestFella/Mustard,
PR #7, since cleaned up). Ready to build. Decision recorded in **ADR-0007**.
**Relates to:** `docs/specs/2026-06-15-source-ingestion-foundation.md` (reuses
`SourceProposal`, dedupe, provenance, scheduling), ADR-0003, ADR-0001.
**Date:** 2026-06-15

## Why this exists

Local headless `claude -p` (Mustard's `ClaudeRunner`) **cannot reach the claude.ai
Gmail connector** — proven empirically, it returns `NONE`. Two ways to get email in:

- **(A) Mac-anchored OAuth** — Mustard owns Gmail via its own OAuth fetch (mirrors
  `Calendar/`). Robust, but needs the Google OAuth client id and only sweeps while
  the Mac is awake.
- **(B) Cloud scout (this doc)** — a Claude Code **routine** reads Gmail via the
  connector (which routines *do* get) and hands candidates to the Mac. Routines are
  effectively free at **≤25 runs / rolling 24h** (hourly = 24/day).

This designs (B) as a **thin scout**: the routine *only discovers and hands off*.
The Mac keeps the entire triage → approve → execute → review loop and **SwiftData
stays the source of truth** — so **ADR-0001 is untouched** and the OAuth build is
avoided.

## Verification gate (run this FIRST, before any build)

Two unknowns decide whether (B) is viable. Prove them with a throwaway routine
against a **test** GitHub repo (not the real vault). Paste this as the routine
prompt, schedule it once (or run manually), then read the routine's output + check
the repo for a `scout-test` branch.

```
You are a one-off verification probe. Do TWO checks, then write results to this
repo and push. Be privacy-preserving: report only counts and success/failure —
do NOT copy email subjects, bodies, sender addresses, or any private content into
the file or your output.

CHECK 1 — Gmail connector reachable from a routine:
- Call the Gmail tool to COUNT how many email threads arrived in the last 24h.
- Record: did the call succeed (yes/no)? If yes, the integer count. If no, the
  exact error/refusal text. Do not read or record message contents.

CHECK 2 — this routine can push to this private repo:
- Write `_scout-test/result.md` containing CHECK 1's outcome, a UTC timestamp,
  and the current commit SHA.
- Run: git checkout -b scout-test && git add _scout-test/result.md &&
  git commit -m "scout verification probe" && git push -u origin scout-test
- Record whether the push succeeded; if not, the exact git error.

FINAL OUTPUT — print exactly this and nothing sensitive:
  GMAIL_TOOL_CALLABLE: yes|no
  GMAIL_THREADS_LAST_24H: <int or n/a>
  GMAIL_ERROR: <none or exact error>
  GIT_PUSH_OK: yes|no
  GIT_ERROR: <none or exact error>
  BRANCH_PUSHED: scout-test|n/a
```

**PASS = `GMAIL_TOOL_CALLABLE: yes` AND `GIT_PUSH_OK: yes`.** If either fails:

- Gmail flaky/no (bug #37789) → fall back to **(A) Mac-anchored OAuth**; nothing
  else in this doc is wasted because the foundation is shared.
- Push fails (bug #64130) → retry with the vault as the routine's *own* attached
  repo (a different code path than cross-repo `GITHUB_TOKEN` access); if still
  failing, (B) is not viable yet → fall back to (A).

## Architecture (once PASS)

```
CLOUD (hourly routine, runs in a clone of the vault repo)
  Gmail connector ─┐
  vault files (cwd)─┤→ discover + ground → write _inbox/<sourceEventID>.json → git push
                              (the routine is the ONLY writer to the repo)
                                   │  GitHub (private vault repo)
                                   ▼
MAC (Mustard.app)
  git pull (read-only) → InboxIngest: parse → filter → dedupe → insert pending Recommendation
                                   │
                                   ▼  unchanged from here on
  triage → approve → execute (claude -p, local) → OutputCard → review → CloudKit → iOS observes
```

## Single-writer contract (the load-bearing invariant)

**The routine is the only writer to the vault repo. The Mac is read-only (`git
pull`).** Consequences: zero git merge conflicts, and the Mac needs **no push
credentials**. The Mac never deletes or moves inbox files; it relies on its
existing dedupe to ignore ones it has already ingested.

## Inbox file format

One file per candidate, named by event id for natural idempotency:
`_inbox/<sourceEventID>.json`. The payload is a serialized `SourceProposal` (the
foundation type) plus a schema version:

```json
{
  "schema": 1,
  "source": "gmail",
  "sourceItemID": "<thread-id>",
  "sourceEventID": "<message-id>",
  "sourceContext": "Jira · PROJ-123 · new comment from Alice",
  "sourceURL": "https://...",
  "occurredAt": "2026-06-15T02:10:00Z",
  "senderDomain": "client.com",
  "title": "short imperative title",
  "body": "1-3 sentences: what and why",
  "actionType": "draft_email",
  "confidence": 0.8,
  "reasoning": "email thread + vault note DEF-123",
  "draft": "proposed content"
}
```

## The routine (hourly)

1. `git pull` (it runs in a clone of the vault repo).
2. Discover via the Gmail connector: client-domain emails + Jira/Shortcut
   notification emails in the lookback window.
3. **Ground locally** — the vault is the cwd, so grep it directly for ticket keys,
   defect ids, project/client names found in each candidate. (This makes the
   two-pass "discover → gather context" cheap and real, not a single heavy prompt.)
4. For each event whose `_inbox/<id>.json` does **not** already exist, write the
   file above.
5. **Prune** `_inbox/*.json` older than the lookback window (keeps the folder
   bounded; the Mac has already ingested them).
6. `git add -A && git commit && git push`.

## The Mac ingest step (`InboxIngest`, new)

On app foreground / the existing 60s loop:

1. `git pull` the vault repo (read-only).
2. Read `_inbox/*.json`; **parse + validate** each (reject malformed / missing
   identity — same parser-enforced discipline as the foundation; the Mac now sees
   the file content, so the **domain allow-list is enforced Mac-side** over
   `senderDomain`, deterministically).
3. Map to `SourceProposal` → run the **existing dedupe** → insert non-duplicate
   pending `Recommendation`s (stamping source identity + `vaultPath`).
4. No writes back to the repo. Files an event already in SwiftData (matching
   `sourceEventID`) are simply skipped — the existing dedupe is the backstop, so
   lingering inbox files are harmless.

Pure where it counts: parse + validate + dedupe are pure/tested; `git pull`,
file read, and SwiftData insert are the impure shell.

## Idempotency (two layers)

1. **Routine side:** filename = `sourceEventID`, so a re-seen event isn't
   re-written; pruning only removes events already outside the lookback window.
2. **Mac side:** the foundation dedupe keyed on `(source, sourceEventID)` drops any
   file whose event is already a Recommendation — the authoritative backstop.

## Cadence math (the 25/24h budget)

| Interval | Runs/24h | Cost |
|---|---|---|
| Hourly | 24 | **Free** (1 spare) |
| Every 90 min | 16 | **Free** (headroom for manual/test runs + a daily vault routine) |
| Every 30 min | 48 | 23 metered (opt-in only) |

**Recommend every 60–90 min.** Note manual test runs also draw from the 25/day, so
90 min leaves slack.

## What changes / what doesn't

- **Unchanged:** SwiftData as source of truth (ADR-0001), the whole loop, trust
  auto-run, CloudKit → iOS, and the `SourceProposal`/dedupe/provenance/scheduling
  foundation.
- **Removed:** the need to build Mustard-owned Gmail OAuth.
- **New:** the routine prompt + `InboxIngest` (pull, validate, dedupe, insert).
- **GmailSource** is no longer "prompt the local CLI to search Gmail"; discovery
  moves to the routine, and `InboxIngest` replaces a local `GmailSource.prompt`.

## Deliberately deferred (YAGNI)

- **Full vault-as-truth** (both clients read the vault, Mac optional) — bigger
  pivot that reopens ADR-0001; only if Mac-independent mobile becomes a hard
  requirement.
- **iOS reading the vault directly** — iOS keeps observing SwiftData via CloudKit.
  When the Mac is asleep, new candidates queue in `_inbox/` and flow in on its next
  pull. Acceptable for a personal tool.
- **Cloud execution** — execution stays on the Mac (`claude -p`). Gated email/Slack
  actions are draft-only anyway, and the routine front-loads enough thread + vault
  context into the candidate file to ground the Mac's draft without live Gmail.
```
