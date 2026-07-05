# Notes — vault-backed markdown with wikilinks & backlinks — design spec

- **Date:** 2026-07-05
- **Status:** Draft — awaiting Leon's review
- **Supersedes/affects:** generalizes `FileVaultIO` (today meeting-notes-only) into a whole-vault scanner; piggybacks reindexing on `SweepScheduler`; adds a new `Notes` top-level surface, `Logic/WikilinkIndex.swift`, and a `NoteIndexEntry` SwiftData model. Nothing existing is removed.

## Why

Leon wants native markdown documentation in Mustard, for three reasons: it sits on disk as plain files, the AI agent reads it well, and wikilinks/backlinks are valuable — especially with AI in the loop. Mustard already treats markdown as a first-class citizen (`VaultSweep`/`FileVaultIO` read/write the vault, `InboxLog` appends curated Keep entries — ADR-0009), but there's no native surface to browse, edit, or link notes inside the app; today that means leaving Mustard for Obsidian, and there's no way to see backlinks or attach docs to tasks from within the app.

A research pass across Bear, NotePlan, Craft, Hubble.md, and Tolaria.md (2026-07-05, see **Research learnings** below) confirmed the direction: a vault-file-native model — real `.md` files, not a proprietary/database-only format — is what makes both "AI reads it well" (agents can grep/read freely, exactly like Tolaria and Hubble.md are built for) and "sits in a repo" true at once. NotePlan is the closest existing analog and already proves notes-linked-to-tasks works well in a small-team-built app.

## Scope

This spec is **Phase A of 3**. Build order:

| Phase | What | This spec |
|---|---|---|
| **A. Foundation** | Vault-file-native notes, native viewer/editor, wikilinks, backlinks panel, SwiftData index mirror | **In scope** |
| B. Attach to work | Tasks/Areas/Projects link to notes (frontmatter `task_id`/`area` field), surfaced in Task detail + Area sidebar | Out of scope (sketched only) |
| C. Deeper vault citizenship | Full-text search, tag filtering UI, Bear/Craft-style inline rich editor, structured frontmatter/properties UI | Out of scope |

**Explicitly out of scope for Phase A:** everything in Phase B/C above, plus mobile *editing* (mobile inherits read-only viewing once CloudKit sync — N2 — lands, via the shared `NoteIndexEntry` model; no new work needed for that to happen), Git-based vault version control (considered, not adopted — see below), agent-built custom views over the notes folder (considered, not adopted), and materializing backlinks into file text (considered, not adopted for Phase A).

## Architecture

**Storage.** Real `.md` files are the source of truth, read/written via a generalized vault adapter (extends the `FileVaultIO` pattern beyond its current meeting-notes-only enumeration). New notes created in Mustard default into `<project>/notes/`, but browsing, opening, editing, and backlink resolution work across **every** `.md` file in a configured project — not just that new folder.

**Multi-project, not a single vault.** Mustard has no single global vault path — `SourceSettings.sources` (`Logic/SourceSettings.swift`) holds one `SourceConfig` per KB, each with its own `workingDirectory`, already swept independently (`AgentService.sweepAllSources`). Notes follows the same model: the Notes surface scans every enabled `SourceConfig`, one project at a time, keyed by `(projectId, relativePath)` exactly like existing per-project state (`upsertState`).

**Ignore rules.** Reuses the structural prune set already in `FileVaultIO` (`node_modules`, `.git`, `.build`, `_artifacts`) plus the ADR-0009 ignore set (`.obsidian/`, `_recs/`). `_filed/inbox-log.md` **stays visible** here — this is a human-browsing surface, not the sweep-proposal path ADR-0009 needed to protect from re-looping.

**Mobile / CloudKit story.** A new SwiftData model, `NoteIndexEntry`, mirrors every scanned note (metadata + a content snapshot). Desktop always writes to the vault file first, then updates the mirror. This is the same vault-file ↔ SwiftData-mirror shape as `FileVaultIO`/`InboxLog` already use. Mobile has no filesystem access to the Mac's vault and no agent (ADR-0003, Mac-only), so it can only ever *view* notes via the synced mirror — and only once CloudKit sync (N2, still Leon-gated on an Apple Developer account) is wired. That asymmetry mirrors the one already accepted for the agent itself.

**Reindexing.** A pure filesystem scan (no `claude -p`, no cost) rebuilds the index per project — piggybacked on the existing `SweepScheduler` cadence so backlinks stay fresh even when files change outside Mustard (e.g. edited directly in Obsidian), plus an immediate local reindex of the file just saved, plus a manual "reindex" in the command bar. Each reindex rebuilds the project's entries wholesale rather than diffing incrementally — vault sizes here are hundreds of files, not tens of thousands, so a full rescan stays cheap and avoids stale-edge bugs from incremental patching.

## Data model

**`NoteIndexEntry`** (new `@Model`):
- `projectId: SourceID` (matches `SourceConfig.id`, a `String`-backed enum)
- `relativePath: String`
- `title: String` (frontmatter `title:` override, else first `# Heading` line, else filename)
- `tags: [String]` (parsed from frontmatter)
- `lastModified: Date`
- `forwardLinks: [String]` (relative paths this note links to)
- `contentSnapshot: String` (raw file content, for the future mobile-view mirror)

**`Logic/WikilinkIndex.swift`** (new, pure, TDD'd): given a project's `[(relativePath, content)]`:
- Parses and strips YAML frontmatter (tags, optional title override) — read-only in Phase A; no structured editor, Leon still hand-edits the YAML block as text. Reserves a `task_id`/`area` field for Phase B.
- Extracts `[[Target]]` and `[[Target|Alias]]` occurrences from the body.
- Resolves each `Target` to a note by filename (case-insensitive, extension stripped) anywhere in the project — **first match wins** if duplicate titles exist elsewhere in the tree (a known MVP limitation, not silently wrong — surfaced in the UI if it matters in practice).
- Builds the inverse graph: for each note, which notes reference it, with the containing line/paragraph as context, so the backlinks panel can show a snippet rather than a bare title list.

## UI

- **Nav:** new **"Notes"** top-level tab, peer to Today/Board/Week/Agent.
- **Sidebar:** grouped by project (the same `SourceConfig` entries already configured in Agent console → Source Settings), each expandable into its real folder tree — mirrors the existing Areas/Lists sidebar pattern rather than a new widget. A filter box narrows the tree by filename/title (full-text search is a Phase C idea).
- **Editor:** raw markdown source with light syntax cues (headers/bold/wikilinks), plus a Source/Preview toggle that renders it — the lowest-risk editor option, chosen explicitly over a custom inline-rich-styling editor (Bear/Craft-style) which is a much bigger SwiftUI build with no off-the-shelf component. Frontmatter is visible/edited as raw YAML text at the top of the source.
- **Backlinks panel:** collapsible, below the editor, listing notes that link to the current one — computed live from `NoteIndexEntry`/`WikilinkIndex`, never written into the file (see **Research learnings** for why the file-mutation alternative was considered and rejected).
- **Wikilinks:** clicking `[[Title]]` in preview mode navigates to the resolved note; if none resolves, offers "Create note titled X."
- **New note creation:** a "+" in the sidebar creates a file in the currently-open project's `notes/` folder with a minimal frontmatter stub.

**Visual direction:** Phase A ships with Mustard's existing `Theme` tokens (warm off-white, hairline dividers, generous spacing) — no new visual language. Leon wants an eventual Craft-inspired feel (spacious, card-like, polished inline rendering), but that's an editor-interaction problem for Phase C, not a Phase A storage or layout decision — Craft itself isn't markdown-native under the hood, so its polish is worth borrowing visually, not architecturally.

## Testing (TDD per CLAUDE.md)

Pure logic, tests first, fixed fixtures (no ambient FS/clock):
- `WikilinkIndex`: `[[Target]]` / `[[Target|Alias]]` extraction, frontmatter tag/title parsing, forward/backlink graph construction (including the containing-line context for snippets), duplicate-title resolution behavior, ignore-list pruning.
- Generalized vault scanner: enumerates all `.md` files honoring the prune/ignore set, via an injected fake `FileManager`/directory structure — same pattern `FileVaultIO`'s existing tests already use for the meeting-notes-only enumerator.
- `NoteIndexEntry` reindex wiring: per-project rebuild triggered by schedule, by save, and by manual reindex — injected fake IO, no real filesystem/timers in tests.

Views verified by `swift build` + Leon's eye, per project convention (no UI unit tests).

## Research learnings (2026-07-05)

A quick pass over the apps Leon referenced, to ground the architecture rather than guess:

- **Bear** — tags only, no wikilinks/backlinks at all. Confirms that a calm, simple feel doesn't require a link graph — validates keeping "editor polish" and "backlink graph" as separate concerns rather than one big feature.
- **NotePlan** — markdown + tasks + calendar in one app, explicit wikilinks with a backlinks panel, and notes link directly to tasks already. The closest existing precedent for both this spec and Phase B, built by a small team.
- **Craft** — confirmed *not* markdown-native (proprietary block model, exports to markdown). Good UI/UX reference for the inline-rich-styling Leon wants eventually, but that's an editor-interaction problem, not a storage-format one — reinforces deferring it to Phase C.
- **Hubble.md** (open source, Electron + Tiptap) — built explicitly as "a notepad for you and your agents": live-reloads as a coding agent edits the notes folder directly. Validates the reindex-on-file-change piece of this design. Uses YAML frontmatter for note properties. Also has an "agent builds custom HTML views over your notes folder" feature — interesting, but likely conflicts with Mustard's calm/curated design philosophy; considered and not adopted.
- **Tolaria.md** — the strongest validation: "just files on your disk, no database, no proprietary format," YAML frontmatter, `[[wikilinks]]` with autocomplete, "rich relationships as first-class citizen" (worth mirroring in Phase B), a fully integrated Git client for version control/sync across devices, and built explicitly for CLI coding agents (Claude Code named specifically) to do tool-backed editing against the vault — the same shape as Mustard's `ClaudeRunner`/vault-cwd model. Git-as-sync is a genuinely interesting alternative to CloudKit for the vault specifically, but out of scope here — Mustard's persistence is CloudKit-shaped by design (ADR-0001) and a parallel Git-sync mechanism for just the vault would be a separate architectural track, not a Phase A/B/C item.
- **note-link-janitor** (a tangential open-source tool, not one Leon listed) — writes a maintained "## Backlinks" section directly into each file, regenerated idempotently. That makes backlinks visible even outside Mustard, but means the app silently rewrites files on every reindex — which cuts against the review/trust philosophy the rest of Mustard is built on (`TrustPolicy`, gated writes). Considered and rejected for Phase A; recorded as a possible later opt-in.

## Open questions / risks

- **Duplicate note titles:** `[[Title]]` resolves to the first match found in a project; a vault with reused titles across folders could resolve to the wrong note. Revisit if it bites in practice.
- **Frontmatter UX:** parsed for the index but not surfaced in a structured editor in Phase A — Leon hand-edits YAML as text. Fine for a technical user; revisit if it's friction once Phase B needs a `task_id`/`area` field written back.
- **Reindex cost at scale:** assumed cheap for hundreds of files; if a configured project's folder balloons (e.g. an embedded code project, as already seen with `node_modules`-heavy KBs), the prune set has to keep up — the same risk `FileVaultIO` already carries today, not a new one.
- **CloudKit gating:** mobile note viewing has no code path to actually test until N2 (Apple Developer account) lands — this spec only guarantees the shared model is ready for it, not that it works end-to-end today.
