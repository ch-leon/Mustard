# Meeting tasks → Leon-actionable only

**Date:** 2026-06-24
**Status:** Draft — awaiting Leon's review
**Author:** brainstormed with Claude

## Problem

Mustard's inbox is being flooded with tasks harvested from meeting notes. Of
278 checkbox lines harvested across 55 meeting notes, only ~71 (26%) are
actually Leon's — the rest are owned by teammates (Graham, Tom, Alex, Tatiana,
Liz, Angelino…), team/role-level ("Code Heroes", "dev team", "lead"), or
unowned. Every one of them lands in Leon's inbox as `owner: .me`.

## Root cause — a contract mismatch between two tools

Two tools disagree on what the "Code Heroes tasks" section *means*:

- **The `sync-meeting` skill** (`Codeheroes work/.claude/skills/sync-meeting/SKILL.md`,
  Step 4) deliberately curates `## Code Heroes tasks` as a **whole-team** list:
  *"only include action items that CH owns OR that CH directly depends on."*
  Correct for meeting minutes in a knowledge base.
- **Mustard's `MeetingTaskSync`** (`Sources/MustardKit/Agent/MeetingTaskSync.swift`)
  reads that exact heading and imports **every line as Leon's task**, straight to
  the inbox — bypassing the recommendation/confidence/triage gate that everything
  else in the agent loop goes through.

Neither side is wrong alone; the heading means *"the team's tasks"* to the skill
and *"Leon's tasks"* to Mustard. That mismatch is the entire bug.

## Decision

Fix it **at the source — the `sync-meeting` skill** — by changing what it writes
under the task heading from *team-actionable* to **Leon-actionable**. Then the
section at the bottom of each note *is* Leon's list by construction, Mustard
imports it unchanged, and **no Mustard filtering logic is added.**

The skill already has the data this needs: the `attendees:` frontmatter (and
prose like *"(Alex absent)"*) tells it who was present, and Step 5 already
resolves names against the vault's `people/` so it knows who is a CH member vs.
external.

## Desired behaviour — the extraction rule

An action item from a meeting becomes a task in the `## Code Heroes tasks`
section **only if one of these holds:**

1. **Leon owns it** → include as-is.
2. **A Code Heroes member owns it, but they were _not_ an attendee** → include,
   reframed as a request Leon must make:
   `Request [[Tom]] to <action>` / `Follow up with [[Tom]]: <action>`.
   Owner becomes `[[Leon Creed-Baker]]` (it is now Leon's action); the original
   assignee is named in the text.
3. **No owner / "not stated" / team-or-role-level owner** ("Code Heroes",
   "dev team", "lead", "DLA dev"…) → include as Leon's (his to do or to
   delegate). This is Leon's stated "mine + unowned" default.

It is **excluded** from the task section when:

4. **A Code Heroes member owns it and they were present** → they heard it; it is
   theirs, not Leon's. It remains documented in `## Discussion` (the standup
   notes), so nothing is lost from the minutes.
5. **A partner / external person owns it** → unchanged from today: goes to
   `## Waiting on others`, not the task list.

### Edge cases

- **Multiple owners** ("Tom / Alex"): if Leon is among them → his. Otherwise, for
  each named CH owner who was absent, include a reframed request; if all named CH
  owners were present, exclude.
- **Citations and tags unchanged**: keep `— [T: "quote"]` and the
  `#task #<topic> #ch` trailer on every line, exactly as today (Mustard harvests
  the checkbox regardless of tags, but consistency matters for the KB).

## Scope of changes

### Part 1 — `sync-meeting` skill (the fix)

File: `Codeheroes work/.claude/skills/sync-meeting/SKILL.md` (the vault repo, **not**
Mustard). Per Leon's note, that repo has tracked secrets — edit locally, **never
push it.**

- **Step 4 ("Extract signal"):** replace the "Code-Heroes-first filter" paragraph
  with the Leon-actionable rule above. Spell out present-vs-absent and the
  reframing convention explicitly.
- **Step 6 (note template):** keep the heading exactly `## Code Heroes tasks` (so
  Mustard keeps importing with no change — confirmed with Leon, no rename). Update
  the inline example line to show a reframed request, and add a one-line comment
  that this section is Leon-actionable only.
- **Step 5 (attendees):** no change needed; it already resolves the attendee list
  the rule consumes. Optionally add a sentence pointing Step 4 at it.

### Part 2 — Mustard one-time backlog cleanup

The skill change only affects **future** syncs. The 182 existing notes keep their
team-level lines, and Mustard has already imported the flood. Per Leon: **mark any
meeting-sourced task from a meeting older than a week as done.**

- **New pure unit** `Logic/MeetingTaskCleanup.swift`:
  `tasksToArchive(_ tasks: [MustardTask], now: Date, olderThan days: Int = 7) -> [MustardTask]`
  — selects tasks where `source` is a meeting source **and** the meeting date is
  more than `days` before `now`. The meeting date is parsed from the note path in
  `task.sourceURL` (e.g. `…/meetings/2026/05/2026-05-29-slug.md` → 2026-05-29) via
  a small, testable helper. Today is 2026-06-24, so this archives meetings before
  2026-06-17.
- **Runner** in `AgentService`: a one-shot, guarded by a `UserDefaults` flag
  (`didArchiveStaleMeetingTasks`) so it runs exactly once. For each selected task:
  `markDone(now:)` **and** set `source = "meeting:archived"` (a sentinel).
- **Prevent vault write-back (deliberate — does NOT modify vault files):** the
  write-back guard in `completeInVault` stays `task.source == "meeting"`, so
  `"meeting:archived"` tasks are skipped → no `✅` is written into the notes.
- **Prevent re-import / re-flood:** widen the dedup match in
  `existingMeetingTasksByKey()` from `source == "meeting"` to
  `source.hasPrefix("meeting")`, so archived tasks still suppress re-creation of
  the same line. (Without this, clearing/retagging would let old lines re-import
  as fresh tasks.)
- **Audit** all other `source == "meeting"` comparisons (views, source
  badges/pills) and decide exact-vs-prefix per call site — archived tasks are done
  and out of active views, so most can stay exact.

## Non-goals (YAGNI)

- **No ongoing auto-complete.** The "older than a week → done" rule is a *one-time*
  backlog cleanup, not a recurring behaviour — real future tasks must not silently
  vanish after a week.
- **No re-sync of the 182 existing notes.** Going-forward only (Leon's choice). The
  cleanup clears the inbox; old notes keep their historical team lists.
- **No Mustard-side owner/attendee filtering.** The judgment lives in the skill,
  where the transcript context is. Mustard stays a dumb lifter.
- **No heading rename.** `## Code Heroes tasks` stays (now meaning Leon's CH tasks).
- **No new "team actions" section.** Teammates' present-owner items stay in
  `## Discussion`; we don't duplicate them anywhere.

## Testing

- **Skill (prompt, not XCTest-able):** dry-run the new Step 4 rule against 2–3
  representative existing notes (e.g. the 2026-05-29 filters-on-friday note, which
  has 5 mixed-owner lines incl. an absent member) and confirm only Leon-actionable
  items survive and absent-member items are reframed as requests. Then eyeball the
  next real `/sync-meeting`.
- **Mustard cleanup (TDD, pure):** unit-test `MeetingTaskCleanup.tasksToArchive`
  with pinned UTC dates and fixture tasks — meeting-dated >7d archived, ≤7d kept,
  non-meeting sources untouched, undated/unparseable paths handled. Unit-test the
  note-path → date helper. Unit-test that dedup with `hasPrefix("meeting")` still
  suppresses re-import of an archived line. `swift test` + `swift build` must pass.

## Risks & mitigations

- **Write-back mutating vault files** → mitigated: archived sentinel skips the
  `source == "meeting"` write-back guard, so notes are untouched. *(Open for Leon:
  flip to write-back-on if you'd rather the note lines be ticked too.)*
- **Re-flood after cleanup** → mitigated by the `hasPrefix("meeting")` dedup widen.
- **Skill judgment is non-deterministic** → the rule is explicit and the data
  (attendees) is structured; spot-check the first few syncs.
- **A genuinely-Leon item mis-tagged to a present teammate** would be dropped → low
  stakes (still visible in Discussion); acceptable given the 74% noise reduction.

## Rollout

1. Edit the skill (Part 1). Effective on the next sync.
2. Land the Mustard cleanup (Part 2); it runs once on next launch and clears the
   backlog inbox without touching the vault.
