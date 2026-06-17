# Meeting Task Ingest — Plan (spec-ready)

> Bring tasks from meeting transcripts into Mustard. Decisions locked with Leon
> 2026-06-16. Buildable / unblocked — reads & writes local vault files only, no
> external creds. Mirrors the capture style of the F14 week-planner plan.

## The key reframe (why this is small)

Leon already runs a **Meeting Sync pipeline** (Triage → Sync → Review) over his
Code Heroes Notion meetings DB. Its **Sync** stage writes a curated meeting note
per meeting into the routed vault, and that note already contains a
**"Code Heroes tasks"** section in **Obsidian Tasks syntax** (`- [ ] …`),
owner-filtered (Code-Heroes-first) and citation-backed. (See Leon's
`meetingsyncplan.md`, §5 step 6.)

Extraction is therefore **already solved**. Mustard must NOT re-read transcripts
or re-derive owners — that would duplicate the pipeline and re-introduce
hallucination risk. Mustard's job is the small bridge:

> **Harvest the already-curated `- [ ]` task lines out of the meeting notes the
> Sync agent writes, into Mustard's task store — and reflect completion back.**

This supersedes the "meetings" half of backlog item **N3** (which assumed an MCP
triage source); the vault-harvest path is simpler and needs no MCP wiring.

## Locked decisions (2026-06-16)

| Decision | Outcome |
|---|---|
| Re-extract from transcripts, or harvest curated lines? | **Harvest** the `- [ ]` lines — no `claude -p`, deterministic, testable |
| Entry point | **Straight into the inbox as tasks** (status `.inbox`, owner `.me`). The Review pass already vetted them; the sweep digest is the record, so it's not "silent" |
| Which lines | **"Code Heroes tasks" section only** (Leon's action items). Not "Follow-ups" / "Waiting on others" for v1 |
| Sync direction | **Two-way.** Completing in Mustard ticks the note's checkbox; a line checked in the vault completes the Mustard task on next sweep |
| Vault → organisation | Point Mustard at `Codeheroes work/`; map each sub-vault (DL / SB / Sandvik / Code Heroes) to a Mustard **Area** so tasks land pre-sorted by client |
| Reversibility for vault writes | **Snapshot-before-edit** to `<vault>/hub/.snapshots/<file>.<ts>.md` (write-only copy — the vault blocks deletes), matching the pipeline's safety net |

## Architecture

A pure parser in `Logic/` + a thin ingest/write-back service. No new agent, no
transcript handling, no model-call on the read path.

```
meetings/**/*.md  ──(MeetingTaskParser, pure)──▶  [ParsedMeetingTask]
        ▲                                                 │
        │ tick line on done (snapshot first)              ▼
 MeetingTaskSync ◀────────────────────────────  upsert into SwiftData
 (locate by originKey, rewrite - [ ] → - [x] ✅)         (MustardTask, status .inbox)
```

### 1. `Logic/MeetingTaskParser.swift` (pure, TDD)

- Input: a meeting note's text + its relative path.
- Find the **"Code Heroes tasks"** section (heading match, tolerant of `##`/`###`
  and trailing text); collect Obsidian Tasks lines under it until the next heading.
- For each line, parse: checkbox state (`[ ]` vs `[x]`/`[X]`), the task text, and
  recognised Obsidian Tasks fields if present — due `📅 YYYY-MM-DD`, done
  `✅ YYYY-MM-DD`, priority emoji. Strip block ids (`^abc`) from the title but keep
  for locating.
- Emit `ParsedMeetingTask { title, isDone, due: Date?, rawLine, notePath, originKey }`.
- `originKey = sha256(notePath + "\n" + normalizedLineText)` — stable identity for
  dedup and for re-locating the line on write-back. Normalisation strips the
  checkbox marker and the `✅ <date>` so ticking a line doesn't change its key.

### 2. New `MustardTask` provenance fields (schema)

`MustardTask` currently has no source fields (those live on `Recommendation`).
Add — all defaulted/optional, CloudKit-safe:

```swift
public var source: String = "manual"     // "meeting" for imported
public var sourceURL: String?            // note path (relative to vault root)
public var sourceContext: String = ""    // meeting title + date, for the row subtitle
public var originKey: String?            // dedup + line locator (see parser)
```

### 3. `Agent/MeetingTaskSync.swift` (the bridge service)

Runs as part of (or alongside) the existing sweep. Injects the vault root and a
file reader/writer so it stays testable.

**Import (vault → Mustard):**
1. Enumerate `meetings/**/*.md`; parse each with `MeetingTaskParser`.
2. For each parsed task, look up an existing `MustardTask` by `originKey`:
   - none + line unchecked → create task (`.inbox`, `.me`, `source="meeting"`,
     `sourceURL`, `sourceContext`, `due` if present), assign to the client **Area**
     derived from the note's vault root (DL/SB/Sandvik/CH → Area).
   - none + line already `[x]` → import as already-done (don't resurrect).
   - exists + line now `[x]` but task open → `task.markDone()` (vault won the race).
   - exists + open → no-op (dedup).
3. Report a digest: "imported N meeting tasks (M clients)" — the not-silent record.

**Write-back (Mustard → vault), on completion:**
1. When a `source=="meeting"` task is marked done, find its note via `sourceURL`.
2. **Snapshot** the note to `<vault>/hub/.snapshots/<file>.<ISO8601min>.md` first
   (copy/write only — no delete).
3. Re-scan the note, find the line whose `originKey` matches, rewrite
   `- [ ]` → `- [x] ✅ <today>` (Obsidian Tasks completion convention). Write the
   file back. Leave everything else byte-identical.
4. If the line can't be found (note moved/edited), skip the write and flag in the
   digest rather than guessing.

### 4. Vault → Area mapping

A small table (DL → "Digital Licence", SB → "Sales Buddi", Sandvik → "Sandvik",
Code Heroes → "Code Heroes"), creating the Area + a default TaskList on first use.
Derive the client from the meeting note's path under `Codeheroes work/<vault>/…`.

## Testing (per project TDD rule)

- `MeetingTaskParserTests` — section detection; checkbox states; due/done date
  parsing; block-id handling; `originKey` stability across tick (key unchanged when
  `- [ ]` → `- [x] ✅ date`); ignores lines outside the "Code Heroes tasks" section.
- `MeetingTaskSyncTests` — create/dedup/skip matrix; vault-won-the-race completion;
  already-done import; Area assignment by vault root; digest counts. Inject an
  in-memory file map (no disk).
- Write-back — snapshot written before edit; only the matched line changes;
  unmatched-line → skip + flag. Pin dates/timezone (AEST vs UTC) per the testing rule.

## Out of scope (v1)

- "Follow-ups" / "Waiting on others" sections (blocked/FYI tasks) — deferred.
- Pulling transcripts or running the Notion pipeline from Mustard — that stays
  Leon's separate pipeline; Mustard only reads its vault output.
- MCP meeting source (the original N3 framing).
- Editing task *text* round-trip — only completion state syncs back.

## Open question for build time

- Cadence: run import on every scheduled sweep, or its own interval? (Cheap —
  it's file I/O + parsing, no model call — so folding it into the 60s sweep loop
  is fine.)
