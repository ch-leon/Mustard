# Agent bridge (Phase 2) — design spec

- **Date:** 2026-06-29
- **Status:** Draft — awaiting Leon's review
- **Phase:** 2 of 3 of the Agent Task Board. Phase 1 (board + `stage` model) merged (PR #26, ADR-0010).
- **Builds on:** the existing `_recs/` → `InboxIngest` pattern (a local routine writes JSON files; Mustard reads them on a ~10-min loop) and `AreaRouter` (area name → KB working directory).

## Why

Phase 1 stages agent work on the board but nothing executes it — a `queued` task just sits there. The bridge is how a **connected Claude session** (Phase 3, with the Shortcut/Gmail connectors and the DL skill) gets its instructions and returns results. Mustard can't execute outward actions itself (headless `claude -p` has no connectors — ADR-0003), and the board lives in SwiftData which a skill can't query — so the two talk through **files in the vault**, mirroring the inbound `_recs/` contract that already works.

## Scope

Phase 2 builds **Mustard's two halves — export and ingest — plus the documented file contract.** Both work-order directions are in scope:
- **execute**: `queued` task → session runs it → result returns into `needsReview` (with links).
- **prep**: `forAgent` task → session fleshes it out → result returns into `needsApproval`.

**Out of scope:** the connected-session worker that reads outbox and writes results (that is **Phase 3**); real connector execution. Phase 2 ships with a manual/stub test against the contract.

**Mobile constraint (load-bearing):** export must be a **pure function of synced board state** — no Mac-only assumptions about *which* tasks qualify. The board is CloudKit-shaped (ADR-0001/0004); a future iOS app is a control surface (queue/approve/review syncs via CloudKit), while execution stays Mac-tethered (the bridge is Mac-local files + a connected session). Mac-*off* mobile execution is the separately-deferred "Mac-independence" pivot and is NOT addressed here.

## Folder protocol

Under each KB working directory (routed by `AreaRouter.workingDirectory(forArea:sources:workVaultRoot:)`):

```
<KB>/_agent/
  outbox/         Mustard writes work orders here       (Mustard owns writes)
    <uid>.json
    done/         the runner archives a work order here after running it
  results/        the connected session writes outcomes here  (session owns writes)
    <uid>.json
    done/         Mustard archives a result here after applying it
```

**Ownership:** Mustard writes only under `outbox/` (excluding `done/`); the session writes only under `results/` (excluding `done/`). The **consumer archives what it consumed** into the sibling `done/` — the session moves a run work order to `outbox/done/`; Mustard moves an applied result to `results/done/`. Archiving (not deleting) gives an audit trail and guarantees nothing is re-run/re-applied.

**Filename:** `<task.uid>.json`. A re-queued task's prior files already sit in `done/`, so a fresh `<uid>.json` does not collide; a second result before Mustard archives simply overwrites (last wins).

## Lifecycle (one task)

1. Task enters `forAgent` (prep) or `queued` (execute). On the ~10-min loop, **export** routes it to its KB folder and writes `outbox/<uid>.json` — only if no live `outbox/<uid>.json` exists (written once, not every cycle).
2. The session (Phase 3) reads `outbox/`, does the work, writes `results/<uid>.json`, archives the order → `outbox/done/`.
3. On the loop, **ingest** reads `results/*.json`, applies each by `uid` (guarded — see below), archives it → `results/done/`.
4. **Stale-order cancel:** if a task left `forAgent`/`queued` while its order is still live in `outbox/` (not yet picked up), Mustard removes that outbox file on the next loop.

## Schemas

`AgentWorkOrder` (Mustard → `outbox/<uid>.json`):
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
createdAt: String            // ISO8601
```

`AgentResult` (session → `results/<uid>.json`):
```
uid: String
mode: "prep" | "execute"
status: "done" | "failed" | "declined"
// prep:
actionType: String?         // classified action
title: String?              // refined title
body: String?               // prepared draft
// execute:
links: [{label, url}]?       // created artifact links (Shortcut URL, Jira, draft)
summary: String?            // one-line what happened
error: String?              // message when failed
```

Both encode/decode with `JSONEncoder`/`Decoder`, `.iso8601` dates, tolerant of missing optionals — same conventions as `SourceProposal`.

## Apply rules (guarded)

For each decoded result, find the task by `uid`. Apply **only if the task is still at the source stage** for that mode (`prep`→`forAgent`, `execute`→`queued`); otherwise archive without applying (stale guard — the idempotency backstop). Unknown `uid` → archive, no-op.

| mode · status | effect on the task |
|---|---|
| prep · done | set `actionType`, `notes` = prepared body, `title` (if given); stage → `needsApproval` |
| prep · declined | `owner` = me, stage → `planned`, append note "🤖 Agent passed: {summary}" |
| prep · failed | stay `forAgent`; surface `error` on `AgentService.lastError` |
| execute · done | set `links`, append `summary` to notes; stage → `needsReview` |
| execute · failed | stay `queued`; surface `error` on `lastError` |
| execute · declined | `owner` = me, stage → `planned`, note appended |

Applying the same result twice is a no-op (after the first apply the task has left the source stage, so the guard archives the second without effect).

## Components

Pure logic + injected IO (per CLAUDE.md: decisions live in `Logic/`, tested; IO is injected like `ClaudeRun`/`FileVaultIO`).

- `Sources/MustardKit/Logic/BridgeProtocol.swift` — `AgentWorkOrder`, `AgentResult`, `TaskLink` reuse, folder-name constants.
- `Sources/MustardKit/Logic/BridgeExport.swift` (pure) — `plan(tasks:routing:existingOutboxUIDs:) -> (writes: [(dir,AgentWorkOrder)], cancels: [path])`. Selects stage ∈ {forAgent, queued} without a live outbox file; flags stale outbox files whose task left the stage.
- `Sources/MustardKit/Logic/BridgeIngest.swift` (pure) — `plan(results:tasks:) -> [Mutation]` with the guarded apply rules; returns which result files to archive.
- `Sources/MustardKit/Agent/BridgeIO.swift` — a thin `FileManager` wrapper (list/read/write/move) injected into the service; protocol so tests stub it.
- `AgentService.exportWorkOrders(_ settings:)` + `ingestAgentResults(_ settings:)` — thin orchestration: for each enabled source's `workingDirectory`, run the pure planner, perform the IO. Wired into the `MustardApp` ~10-min loop beside `ingestInbox`, behind the same `!isSweeping && !isExecuting` guard. Routed by `AreaRouter`.

## Testing (TDD)

- **BridgeExport:** forAgent→prep order, queued→execute order, in the AreaRouter-resolved folder; skips a task with a live outbox file; cancels a stale outbox file (task left the stage); ignores non-agent stages. JSON round-trip of `AgentWorkOrder`.
- **BridgeIngest:** each mode·status row above; the **stale-stage guard archives without applying**; double-apply is a no-op; unknown `uid` is safe; failed execute stays queued + sets error. JSON decode of `AgentResult` incl. missing optionals.
- **IO:** stubbed for the pure tests; `BridgeIO` covered against a real temp directory (write → list → move-to-done).
- Views/loop wiring verified by `swift build` + Leon's eye.

## Phase 3 boundary

Phase 2 ships export + ingest + this contract, and a manual test: hand-write a `results/<uid>.json` and confirm Mustard applies it correctly. The worker — a skill/routine that reads `outbox/`, runs `dl-create-shortcut-story` (and the email/Slack equivalents) in a connected session, and writes `results/` — is Phase 3, with its own spec.

## Open risks

- **Re-queue collision:** a task re-queued after a completed cycle reuses `<uid>.json`; prior files are in `done/`, so no live collision, but two un-archived results racing would last-win. Acceptable; the stage guard still protects correctness.
- **Orphaned outbox on long Mac-off gaps:** stale-order cancel runs only while the app is open; a work order written then abandoned (task handled on mobile) is cancelled on the next loop when the Mac is next on. Acceptable under the Mac-on stance.
