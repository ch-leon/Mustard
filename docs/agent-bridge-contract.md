# Agent Bridge — File Contract (Phase 2)

This is the interface between **Mustard** (the macOS app) and a **connected Claude
session** (Phase 3: the worker skill/routine with the Shortcut/Gmail connectors and the
DL skill). They cannot call each other directly — headless `claude -p` has no connectors
(ADR-0003) and the board lives in SwiftData a skill can't query — so they talk through
**JSON files in each KB vault**, mirroring the inbound `_recs/` → `InboxIngest` contract.

Phase 2 (this) ships Mustard's two halves: **export** (board → `outbox/`) and **ingest**
(`results/` → board), plus this contract. The **worker** that reads `outbox/`, does the
work, and writes `results/` is **Phase 3** — it implements the session side of this doc.

## Folder protocol

Under each KB working directory (routed by `AreaRouter` from the task's area):

```
<KB>/_agent/
  outbox/         Mustard writes work orders here          (Mustard owns writes)
    <uid>.json
    done/         the session archives a work order here after running it
  results/        the connected session writes outcomes here   (session owns writes)
    <uid>.json
    done/         Mustard archives a result here after applying it
```

**Ownership.** Mustard writes only under `outbox/` (never `outbox/done/`); the session
writes only under `results/` (never `results/done/`). **The consumer archives what it
consumed** into the sibling `done/`: the session moves a run work order to
`outbox/done/`; Mustard moves an applied result to `results/done/`. Archiving (not
deleting) gives an audit trail and guarantees nothing is re-run or re-applied.

Folder names are the constants in `BridgeFolders` (`Sources/MustardKit/Logic/BridgeProtocol.swift`).

**Filename:** `<task.uid>.json`. A re-queued task's prior files already sit in `done/`,
so a fresh `<uid>.json` does not collide. Two live results before Mustard archives → last
wins; the stage guard (below) still protects correctness.

## Lifecycle (one task)

1. A task enters `forAgent` (prep) or `queued` (execute). On Mustard's ~10-min loop,
   **export** routes it to its KB folder and writes `outbox/<uid>.json` — only if no live
   `outbox/<uid>.json` exists already (written once, not every cycle).
2. The session (Phase 3) reads `outbox/`, does the work, writes `results/<uid>.json`, and
   archives the order → `outbox/done/`.
3. On the loop, **ingest** reads `results/*.json`, applies each by `uid` (guarded — see
   the apply table), and archives it → `results/done/`.
4. **Stale-order cancel:** if a task left `forAgent`/`queued` while its order is still live
   in `outbox/` (not yet picked up), Mustard removes that outbox file on the next loop.

## Schemas

Both encode/decode with `JSONEncoder`/`JSONDecoder`, `.iso8601` dates, tolerant of missing
optionals (`BridgeCoding`).

### `AgentWorkOrder` — Mustard → `outbox/<uid>.json`

```
uid: String                 // stable match key (task.uid)
mode: "prep" | "execute"    // derived from stage: forAgent→prep, queued→execute
actionType: String          // task.actionType raw (may be "" for prep, to be classified)
title: String
body: String                // task.notes (the draft/details)
area: String                // task.list?.area?.name (e.g. "Digital Licence")
project: String             // KB folder code (e.g. "DL")
sourceContext: String
links: [{label, url}]        // usually empty on the way out
createdAt: String            // ISO-8601
```

### `AgentResult` — session → `results/<uid>.json`

```
uid: String
mode: "prep" | "execute"
status: "done" | "failed" | "declined"
// prep:
actionType: String?         // classified action (RecommendationAction raw, e.g. "ticket_write")
title: String?              // refined title
body: String?               // prepared draft
// execute:
links: [{label, url}]?       // created artifact links (Shortcut URL, Jira, draft)
summary: String?            // one-line what happened
error: String?              // message when failed
```

## Apply rules (guarded)

For each decoded result, Mustard finds the task by `uid`. It applies **only if the task is
still at the source stage** for that mode (`prep`→`forAgent`, `execute`→`queued`);
otherwise it archives the file without applying (the stale guard — the idempotency
backstop). Unknown `uid` → archive, no-op.

| mode · status     | effect on the task |
|-------------------|--------------------|
| prep · done       | set `actionType`, `notes` = prepared body, `title` (if given); stage → `needsApproval` |
| prep · declined   | `owner` = me, stage → `planned`, append note "🤖 Agent passed on this: {summary}" |
| prep · failed     | stay `forAgent`; surface `error` on `AgentService.lastError` |
| execute · done    | set `links`, append `summary` to notes; stage → `needsReview` |
| execute · failed  | stay `queued`; surface `error` on `lastError` (so the next export re-issues — retry) |
| execute · declined| `owner` = me, stage → `planned`, note appended |

Applying the same result twice is a no-op: after the first apply the task has left the
source stage, so the guard archives the second without effect.

## Worked examples

`outbox/u-9f3a.json` (execute — Mustard wrote this for a `queued` ticket task):

```json
{
  "actionType" : "ticket_write",
  "area" : "Digital Licence",
  "body" : "Driver licence renewal screen crashes on iOS 17 when the camera permission is denied.",
  "createdAt" : "2026-06-29T08:12:00Z",
  "links" : [],
  "mode" : "execute",
  "project" : "DL",
  "sourceContext" : "From standup 2026-06-29",
  "title" : "File bug: licence renewal crash on denied camera permission",
  "uid" : "u-9f3a"
}
```

`results/u-9f3a.json` (the session ran it and wrote this back):

```json
{
  "uid": "u-9f3a",
  "mode": "execute",
  "status": "done",
  "links": [{ "label": "Shortcut", "url": "https://app.shortcut.com/codeheroes/story/12345" }],
  "summary": "Created Shortcut story #12345 in the DL Bugs workflow."
}
```

After ingest, task `u-9f3a` moves to **Needs Review** with the Shortcut link, and the
result file is archived to `results/done/u-9f3a.json`.

A `prep` example — `results/u-77.json` for a `forAgent` task:

```json
{
  "uid": "u-77",
  "mode": "prep",
  "status": "done",
  "actionType": "ticket_write",
  "title": "Raise the SDK BLE timeout to 30s",
  "body": "Prepared story: bump the BLE scan timeout from 10s to 30s; see DIGIDMOB-812..."
}
```

After ingest, task `u-77` moves to **Needs Approval** with the classified action and the
prepared draft as its notes.

## Phase 3 boundary

Phase 2 ships export + ingest + this contract. The **worker** — a skill/routine that reads
`outbox/`, runs `dl-create-shortcut-story` (and the email/Slack equivalents) in a connected
session, writes `results/`, and archives the work order to `outbox/done/` — is **Phase 3**,
with its own spec.

## Manual end-to-end test

This is the Phase-2 acceptance check (Mustard's two halves work against a hand-written
result, standing in for the Phase-3 session):

1. In the app, approve an outward recommendation so a task enters **Approved · Queued**.
2. Confirm `<KB>/_agent/outbox/<uid>.json` appears with `"mode":"execute"`.
3. Hand-write `<KB>/_agent/results/<uid>.json`:
   ```json
   {"uid":"<uid>","mode":"execute","status":"done","links":[{"label":"Shortcut","url":"https://app.shortcut.com/x"}],"summary":"created"}
   ```
4. Wait for the ~10-min loop (or relaunch the app); confirm the task moved to **Needs
   Review** with the link, and the result file is now under `results/done/<uid>.json`.
