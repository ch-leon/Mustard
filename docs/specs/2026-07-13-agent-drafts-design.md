# File-backed Agent Drafts — Design

- **Status:** Approved in conversation; ready for implementation plan
- **Date:** 2026-07-13
- **Depends on:** the agent task-sessions core MVP (F24, `docs/specs/2026-07-13-agent-task-sessions-design.md`)
- **Branch:** `codex/agent-task-sessions-implementation`

## Problem

A completed delegated turn can produce drafted content — a Jira/Shortcut comment, an
email, a Slack message, a note. Today the only place that content can land is the
structured result's prose (`message`/`summary`), and the coordinator stores `summary`
in preference to `message` (`AgentTaskCoordinator.apply(_ result:)`), so a full draft
returned in `message` is **not shown and not retrievable** — only a one-line summary
survives. Large drafts would also bloat the SwiftData conversation. The first real test
task ("Jira Question") surfaced this: the agent drafted a formal Jira reply plus two
guideline URLs, but only the summary was visible.

## Goal

Give every draft a durable, copy-able, in-app home that handles arbitrarily large content,
without sending anything and without converting tasks into notes.

## Approach

A draft **is a vault markdown file**. The worker writes it to the vault (it already has
vault access) and returns a lightweight reference; Mustard records the reference, renders
the file inline in the task, and can open it in the built-in Notes editor. The conversation
keeps only a short line, so the transcript stays lean regardless of draft size.

## Components

### 1. File location & format
- Path: `<vault>/_agent/drafts/<task-uid>/<slug>.md`, namespaced per task, alongside the
  existing `_agent/outbox`/`results`.
- Always markdown. Multiple drafts per task allowed (one file each).
- Files persist (durable record); no auto-cleanup on accept in this iteration.

### 2. Worker contract (`AgentTurnContract` + `MustardAgentContract.md`)
- `AgentTurnResult` gains `drafts: [AgentDraftPayload]` where
  `AgentDraftPayload = { kind: String, title: String, path: String }` (`path` relative to
  the run's working directory).
- `kind` is a small closed set for iconography: `email`, `message`, `comment`, `note`,
  `other` (decoded leniently; unknown → `other`).
- JSON schema updated to include the optional `drafts` array with those required subfields.
- Semantic post-validation: reject absolute paths and any `..` segment — a draft path must
  stay inside `_agent/drafts/` within the working directory. A payload that fails is dropped
  with an error note rather than trusted.
- Contract text (binding): *any drafted content must be written to a file under
  `_agent/drafts/<task-uid>/` and returned in `drafts[]` with its relative path — never
  inline large content in `message`/`summary`. Never send; drafts only.*

### 3. Connected-worker parity (`BridgeProtocol.AgentResult`, `BridgeIngest`, `AgentService`)
- `AgentResult` gains an optional `drafts: [AgentDraftPayload]?`.
- The connected worker writes the same file layout and returns paths.
- `AgentService.normalizeConnectedResult` records draft references identically to the local
  path, so local and connected turns behave the same.

### 4. Storage (`AgentDraft` model)
- New `@Model AgentDraft { uid, kindRaw, title, relativePath, createdAt, run: AgentRun? }`
  with a typed `kind` accessor.
- `AgentRun` gains `@Relationship(deleteRule: .cascade, inverse: \AgentDraft.run) drafts: [AgentDraft]?`
  — drafts reach the task via `run.task` and are cleaned up with the run.
- Only the **reference** is persisted in SwiftData; the body stays on disk.
- Registered in `MustardContainer`, `PreviewData`, and every model test schema that includes
  `MustardTask`/`AgentRun`.

### 5. Coordinator wiring (`AgentTaskCoordinator`)
- On a completed turn (and any outcome that returns drafts), for each validated payload
  create an `AgentDraft` on the run (via a small helper, mirroring the `AgentConversation`
  pattern). The completion message summarises count only ("Drafted 2 items"), never the
  bodies.
- Draft creation participates in the existing narrow snapshot/restore on save failure.

### 6. Display (`AgentDraftsSection` in the task detail; Notes navigation)
- A "Drafts" section (shown when `run.drafts` is non-empty), each row:
  - title + a `kind` icon;
  - the file's markdown **read live** on view via the vault IO + shared `MarkdownBlocksView`
    (no cache — reflects in-app/Notes edits, and large files never enter the store);
  - **Copy** — copies the raw file text (for pasting into Jira/email/etc.);
  - **Open in Notes** — navigates the Notes surface to
    `NoteRef(project: run.project, workingDirectory: run.workingDirectory, relativePath: draft.relativePath)`
    in the built-in Craft editor for in-app editing. (No Obsidian.)
- Missing/moved file → a graceful "draft file not found" state, not a crash.
- Cross-surface navigation from task detail → Notes uses a shared navigation hook (a
  `NoteRef` open-request the Root layer routes to the Notes tab).

### 7. Safety
- Path validation confines drafts to `_agent/drafts/` within the working directory.
- Mustard's file access for drafts is **read-only** (writes happen only in the Notes editor
  the user opens).
- The no-send rule is unchanged and reinforced in the contract.

## Testing
- **Pure:** `AgentTurnContract` decode of `drafts[]`; path-safety validation (absolute / `..`
  rejected). Pin no clock here.
- **Coordinator (stub runtime):** a completed result carrying `drafts[]` creates matching
  `AgentDraft` records on the run; the summary message excludes bodies; invalid paths are
  dropped.
- **Bridge:** a connected `AgentResult` with `drafts` creates `AgentDraft` records via ingest.
- **Model round-trip:** `AgentDraft` persists and resolves through `run.drafts`.
- **View:** build + Leon's eye-check (Drafts section render, Copy, Open in Notes).

## Out of scope (YAGNI)
- Converting tasks into vault notes (separate epic if ever wanted).
- Routing *non-draft* large outputs through files (same mechanism could extend later).
- Auto-cleanup / lifecycle status on draft files (accepted/used/stale).
- Editing a draft directly inside the task detail (Notes editor covers editing).
