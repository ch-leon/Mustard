# Mac App: Agent-Native Task Hub — Design

Date: 2026-06-10
Status: Approved direction (brainstormed); MVP scope decisions made autonomously under `/goal create an mvp of the mac app`.

## Vision

Evolve the Triage Cockpit from a local web app into an **agent-native task hub**:
a native Mac app (iOS later) where Leon and a single Claude agent share a work
surface. The agent runs against the knowledge base on a schedule, **recommends
tasks**, Leon triages them (assign to agent now / schedule later / take it
himself / dismiss), and the agent **surfaces completed work with its output**
for review.

North star reference: Tolaria (local-first, markdown KB, agents inside the app).

## Decisions from brainstorming

| Topic | Decision |
|---|---|
| Why a Mac app | All of: dock-app convenience, native OS integration (floating always-on-top HUD, notch-style UI later), distribution, agents running inside the app |
| iOS | Yes, as a first-class *client* (review/approve/plan); never runs the agent |
| Knowledge base | Stays local markdown on the Mac (Obsidian vault), Git-synced |
| Tasks & structured data | Move out of `.md` / `triage-out` files into a shared backend |
| Backend | Supabase / Postgres (chosen for owned relational data + realtime to both clients) |
| UI technology | Native **Swift/SwiftUI** for macOS + iOS (rewrite accepted; required by notch/floating-HUD ambitions) |
| Agent loop | Stays a **TypeScript/Node worker on the Mac** — the only component touching Claude Code, credentials, and the vault |
| Claude billing | **Claude Code subscription**, not API keys: the worker shells out to `claude -p` (headless print mode) using the CLI's logged-in auth. Worker is therefore bound to the Mac; runs tasks serially and backs off on rate limits |
| Agents | One agent (option A), steered by a **project taxonomy**; schema designed so it could grow |
| Project context | A project anchors to an **area of the knowledge base** (`vault_path`) — option A |

## Core lifecycle

```
[Agent runs on schedule against KB]
        ↓ produces
   RECOMMENDED  ──(dismiss)──▶ dismissed
        │
        ├──(assign now)──▶ QUEUED ──▶ WORKING ──▶ COMPLETED (+ output) ──▶ done
        ├──(schedule later)──▶ QUEUED with scheduled_for ──(time hits)──▶ same path
        └──(I'll do it)──▶ assignee=me, todo → in_progress → done
```

A recommendation is just a task in `recommended` state — no separate table.

## Data model (Postgres/Supabase-shaped; MVP implements it in SQLite)

```
projects      id, name, vault_path, color, created_at
tasks         id, project_id, title, body,
              origin   ('me' | 'agent_recommended'),
              assignee ('me' | 'agent'),
              status   ('recommended'|'queued'|'working'|'completed'
                        |'todo'|'in_progress'|'blocked'|'done'|'dismissed'),
              scheduled_for (nullable timestamp), created_at, updated_at
task_outputs  id, task_id, kind ('summary'|'draft'|'diff'|'link'), content, created_at
agent_runs    id, project_id, task_id (nullable), trigger ('schedule'|'manual'),
              status, started_at, finished_at, log
schedules     id, project_id, kind ('recommend'), cron, enabled, last_run
```

## Architecture

```
┌─ Mac ────────────────────────────────────────────────┐
│  SwiftUI app (TriageHub.app)                          │
│      │  HTTP/JSON + SSE (MVP) / Supabase realtime (v2)│
│      ▼                                                │
│  Node worker (worker/)                                │
│   • owns the store (SQLite MVP → Supabase v2)         │
│   • executor: picks up queued agent tasks serially,   │
│     spawns `claude -p` with cwd = project.vault_path, │
│     writes task_outputs, flips status                 │
│   • recommender: on demand (MVP) / cron (v2), asks    │
│     claude for ≤5 recommended tasks over the KB area  │
└───────────────────────────────────────────────────────┘
   iOS app (later) ──▶ Supabase directly (after v2 swap)
```

## MVP scope (this goal)

**In:**
- `worker/`: Express API on port 3002 + SQLite store (`worker/data/hub.db`),
  schema above; SSE event stream for live updates; serial executor shelling
  to `claude -p --output-format json`; `POST /api/projects/:id/recommend`
  manual recommender trigger.
- `apps/mac/` SwiftUI app, built as a real `TriageHub.app` bundle:
  - Projects sidebar (+ create project with name & vault path)
  - Recommended inbox: assign to agent / take myself / dismiss
  - Task list grouped by status with status controls (no drag-drop yet)
  - Task detail: body, outputs, status actions
  - "Run recommender" button per project
  - Floating always-on-top mini panel (NSPanel) showing the agent's current
    working task — first slice of the Blitz-style HUD
- Worker tests (vitest) for store + API.

**Out (deliberate, for later phases):**
- Supabase swap + iOS app (v2 — blocked locally: no Docker for `supabase start`,
  and hosted Supabase needs account keys; store/API mirror the schema so the
  swap is mechanical)
- Cron scheduling of the recommender (manual trigger in MVP)
- Notch UI, drag-drop kanban, week/calendar view in the Mac app
- Migration of the existing web cockpit data (the web cockpit keeps working
  untouched alongside)

## Error handling

- Worker: a failing `claude` run marks the task `blocked` with the error in
  `agent_runs.log`; executor continues with the next task. Rate-limit errors
  back off (5 min) and requeue.
- App: API errors surface as non-blocking banners; the app retries SSE
  connection with backoff.

## Testing

- Worker: vitest unit tests on the store and supertest API tests, with the
  claude spawn faked.
- Mac app: build verification + manual visual verification (launch + screenshot).
