# BAK-82 — Well-formed tasks from meetings

**Status:** Approved (Leon, 2026-06-30)
**Issue:** [BAK-82](https://linear.app/bakinglions/issue/BAK-82) — Meeting-imported task titles are the full raw action-item line
**Branch:** `leon/bak-82-meeting-imported-task-titles-are-the-full-raw-action-item`

## Problem

Meeting-sourced tasks render with enormous titles because the **title** is set to
almost the entire raw action-item line, and `task.notes` is never populated.

The `sync-meeting` skill (vault-side) writes one Obsidian-Tasks line per task:

```
- [ ] <ACTION> — owner: Code Heroes, due: imminent #task #ch — [T: "transcript quote"]
```

But Mustard's `MeetingTaskParser.extractTitle` only strips the checkbox, `📅`/`✅`
dates, block-ids, and priority emoji — none of which these lines contain. So the
whole `<ACTION> — owner:… due:… #tags — [T:"…"]` string becomes the title, and the
notes/description stays empty.

Two related defects:
- **Giant titles**, no description, no visible meeting reference.
- **Latent due-date bug**: the skill writes `due: <date>` as text, but the parser
  only reads the `📅` emoji — so real due dates never import.

## Outcome

Every meeting-imported task gets:
- a **concise title** (the action clause),
- a **proper description** of what needs doing (authored by the skill from the
  transcript) + a **reference to its meeting**,
- a correct **due date**,
- **topic tags** mapped to `task.tags`.

Delivered as two coordinated parts ("Both"): the `sync-meeting` skill emits a
richer, contract-stable line; Mustard parses it robustly into the task.

## 1. Line-format contract (skill side)

`sync-meeting` keeps one Obsidian-Tasks-compatible line per task and adds a `desc:`
field it authors from the transcript:

```
- [ ] <ACTION> — desc: "<1–2 sentence description of what needs doing>", owner: [[Name]], due: <ISO date | "not stated" | text> #task #topic #ch — [T: "transcript quote"]
```

Guarantees the skill must uphold (so the parser can rely on them):
- The **action clause never contains a spaced em-dash `—`** (use hyphens/colons) —
  it is the title delimiter.
- `desc:` is a quoted 1–2 sentence string; `[T: "…"]` quote stays last.
- This is a **local-only edit** to
  `Codeheroes work/.claude/skills/sync-meeting/SKILL.md`. That repo is never pushed
  (it holds tracked secrets). Only future meetings get the new format; old notes are
  handled by the parser fallback + heal path below.

## 2. Mustard parsing — `MeetingTaskParser`

- **Title** = text before the first ` — ` (spaced em-dash, U+2014). If no ` — ` is
  present, fall back to today's stripping logic — so plain hand-written lines and
  the existing test fixtures still pass (backward compatible). Then strip
  `[[wikilink]]` → inner text and any stray `#tags`.
- Extract from the tail by **anchoring on markers** (order-tolerant), not fixed
  positions: `desc: "…"`, `owner:`, `due:`, `#tags`, `[T: "…"]`.
- **Due**: parse `due: YYYY-MM-DD` → `dueAt`. Keep `📅 YYYY-MM-DD` as a fallback.
  Non-date values (`"imminent"`, `"not stated"`) → `dueAt` nil, text retained for
  the notes footer.
- **Tags**: collect `#tags`, drop the structural `#task`/`#ch`, map the rest →
  `task.tags` (leading `#` stripped).
- `ParsedMeetingTask` gains: `desc`, `owner`, `dueText`, `tags`, `transcriptQuote`.
- `originKey` computation is **unchanged** (still hashes the normalized raw line),
  so existing tasks keep deduping correctly.

## 3. Notes composition — `MeetingTaskSync.makeTask`

```
<desc>                              ← skill-authored; falls back to transcript quote when no desc

From: <meeting title> (<date>)      ← date best-effort from the note path (…/YYYY/MM/YYYY-MM-DD-slug.md)
Context: "<transcript quote>"        ← only when present and distinct from desc
Owner: <owner> · Due: <due text>     ← only the fields that exist
```

Plus `task.tags` set and `task.dueAt` from the parsed `due:`.

## 4. Healing existing giant-title tasks

On import, for a task matched by `originKey` whose `notes` is **empty** AND whose
freshly-parsed concise title **differs** from the stored title, update the title +
notes once. After that `notes` is non-empty, so we never touch it again (won't
clobber manual edits). This cleans up already-imported giant cards on the next
sweep without a separate migration.

## 5. Testing (TDD)

New/changed XCTests:
- **Parser**: title split on ` — `; `desc`/`owner`/`due:`-text/`tags` extraction;
  `"imminent"`/`"not stated"` → nil due; `[[wikilink]]` stripping; tag skip-set
  (`#task`/`#ch`); backward-compat with the old `📅`/`✅` fixtures (no em-dash →
  fallback path).
- **Sync**: `makeTask` notes composition; `task.tags`; `dueAt` from `due:`; the heal
  path (existing empty-notes giant-title task gets updated; a task with non-empty
  notes is left alone).

The skill change is a prompt — documented with an example in `SKILL.md`, no
automated test.

## Out of scope (deferred to follow-ups)

- Board-card title line-cap (defensive board hygiene from BAK-82 — not selected).
- Any model work beyond the `desc:` field.
