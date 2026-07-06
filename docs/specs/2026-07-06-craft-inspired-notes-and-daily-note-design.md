# Craft-inspired Notes editor & agent-drafted Daily Note — design spec

- **Date:** 2026-07-06
- **Status:** Draft — pending Leon's approval (spec gate, per CLAUDE.md workflow gates)
- **Tracker:** TBD — proposed new epic (sub-issues per phase below)
- **Visual reference:** two exploratory mockups produced with Leon this session —
  a general Craft-pass (`craft-mustard-mockups`) and the Notes-focused pass
  (`craft-notes-mockups`). These are HTML stand-ins for SwiftUI on the real `Theme`
  tokens; this spec is the buildable version of what they showed.
- **Supersedes/affects:**
  - **Realises Notes Phase C** parked by `2026-07-05-notes-vault-backlinks-design.md`
    ("Bear/Craft-style inline rich editor"), replacing `NoteEditorView`'s Source/Preview
    toggle with a live editor. Storage (vault `.md` + `NoteIndexEntry` mirror) is
    **unchanged** — only the editing *surface* changes.
  - **Extends the morning ritual** (`2026-07-06-morning-ritual-design.md`) from a
    transient wizard into a persistent, agent-drafted Daily Note document. The wizard
    stays as a fast-path; the *document* becomes the durable artifact.
  - **Adds depth + motion + editorial-type tokens** to `Logic/Theme.swift` (today it
    has surfaces/text/accent but no elevation, animation, radius/spacing, or display
    type scale).
  - Touches `OutputCard` rendering (`AgentConsoleView`), `TodayView`, and the board
    card (`MustardBoardCard`) for the surface-polish pass.
  - Nothing existing is removed.

## Why

Leon likes Craft (craft.do) "from the UI to its features" and wants Mustard —
especially **Notes** — to feel as Craft-like as possible, plus his own idea: fuse the
Daily Note with the morning ritual so the **agent populates it overnight**. The Notes
spec already recorded that Leon "specifically likes Craft's UI" and that "Craft's
polish is worth borrowing visually" — deferring it to Phase C. This spec is that
Phase C, bundled with the small shared groundwork (depth/motion tokens) that every
Craft-like surface leans on, and the Daily Note that best amplifies Mustard's core
thesis ("plan your day and your agents' day together").

## Scope — four phases, dependency-ordered

Each phase is independently shippable and reviewable; later phases depend on earlier.

| Phase | What | Risk | Depends on |
|---|---|---|---|
| **0. Theme foundation** | Elevation (shadow), motion, radius/spacing, and editorial-type tokens in `Theme` | Low | — |
| **1. Surface polish** | Apply the tokens: markdown-render `OutputCard`, card depth + hover on board/output/rec rows, reading typography on Today + output, warmer empty states | Low | 0 |
| **2. Craft live Notes editor** | Replace Source/Preview toggle with a live WYSIWYG editor: document header, inline-rendered markdown, wikilink pills, linked-references card **(2a)**; block hover-handles, `/` slash menu, subpage cards **(2b)** | **High** (NSTextView) | 0 |
| **3. Agent-drafted Daily Note** | A persistent daily `.md` the agent pre-fills (standup, rollover, focus, calendar), edited like any note; ritual fused | Medium | 0, 2a |

**Explicitly out of scope (considered — see Decision log):** dark mode (Mustard is
light-locked by **ADR-0005**; a dark theme needs an ADR revisit + the Xcode/entitlements
move ADR-0004 defers — recorded, not built); focus/typewriter mode; note cover images;
full-text search (a separate Notes Phase C item, adjacent but not required here); mobile
*editing* of notes/daily (parity rule: all pure logic lands in MustardKit so iOS inherits
view-only once CloudKit/N2 lands — no mobile UI in this spec).

---

## Phase 0 — Theme foundation

Pure additions to `Logic/Theme.swift`. No behaviour change until Phase 1 consumes them.
Every value is a token so views never hardcode a shadow or duration (same discipline as
the existing palette).

- **`Theme.Elevation`** — three named shadow recipes matching the mockups:
  - `card` — faint 1px border companion + `0 4px 14px -8px` soft close shadow (board
    cards, output cards, subpage cards, callouts).
  - `float` — `0 14px 36px -14px` lifted shadow (open editor window feel, hover state).
  - `pop` — `0 18px 40px -12px` (slash menu, popovers).
  A small `elevation(_:)` `ViewModifier`/`View` extension applies border + shadow together.
- **`Theme.Motion`** — canonical `Animation` tokens: `settle` (`.snappy(0.16)`),
  `expand` (`.snappy(0.18)`), `pop` (spring for menus). Replaces the ad-hoc
  `.snappy(0.15–0.18)` scattered across Notch/Hover/OutputCard so the app has one feel.
- **`Theme.Metrics`** — radius + spacing scale (`r.sm/md/lg`, `pad.*`) codifying the
  6/7/10/12 radii already used by hand.
- **`Theme.Fonts` editorial additions** — `docTitle` (~33 semibold), `docH1/H2`,
  `reading` (~16 with a line-height intent) for long-form note/output content. The
  existing 15/13/22 tokens stay for chrome.

**Design-language note:** these *extend* "Things 3 calm" (ADR-0005) toward Craft's
warmth without breaking it — depth is soft and optional, motion is quick and quiet.
The notch stays its own dark panel, untouched.

**Testing:** values are declarative; verified by build + the Phase 1 surfaces that use
them. No new pure logic to TDD here.

---

## Phase 1 — Surface polish (apply the tokens)

Low-risk, no schema change; makes the app visibly Craft-warmer immediately.

- **Markdown-render `OutputCard` content.** `OutputCard.content` is already markdown
  (the agent emits it) but the console renders it as plain `Text`. Render it through the
  **existing `MarkdownPreviewView`** block renderer, passing no-op `resolve`/`onWikilinkTap`
  closures (output cards have no wikilink graph). Reuse, not new code. File:
  `Views/AgentConsoleView.swift` (the output-card row) + `Views/MarkdownPreviewView.swift`
  (already parameterised).
- **Card depth + hover-lift.** Apply `Theme.Elevation.card` to `MustardBoardCard`,
  the output-card container, and `RecommendationRow`; add an `onHover` lift
  (`Theme.Motion.settle`, `elevation(.float)`) on board cards so they read as grabbable
  before a drag.
- **Reading typography.** Widen the long-form measure and apply `Theme.Fonts.reading`
  in the output-card body and the Today list; give Today's header the `docTitle`-adjacent
  size and a descriptive date line (it already renders `weekday.day.month`).
- **Warmer empty states.** Replace bare tertiary-text empties (Today "Nothing scheduled
  yet", Notes "Select a note", backlinks "No backlinks yet") with a calm centered glyph +
  one-line invitation.

**Testing:** no new logic — build + Leon's eye. Existing tests stay green.

---

## Phase 2 — Craft live Notes editor (Notes Phase C)

The headline. Replace the Source ↔ Preview toggle in `Views/NoteEditorView.swift` with a
**single always-rendered, editable surface**. **The vault `.md` file stays the source of
truth** — the editor reads/writes markdown text via the existing `FileVaultIO`
(snapshot-guarded save, save-on-switch) and the reuse of `MarkdownBlocks`/`WikilinkSyntax`.
"Blocks" here are a **presentation/interaction layer over text ranges**, not a new stored
block tree (consistent with the Notes spec's file-native architecture — there is no block
database, and we are not adding one).

Split into two sub-phases so the high-value, lower-risk half can ship first (this is the
"live-render first" recommendation from the exploration):

### 2a — Live document surface (lower risk)
- Kill the segmented Source/Preview control. One surface that renders markdown as you
  type (headings sized, `**bold**`/`*italic*`/`` `code` `` styled with the syntax markers
  de-emphasised, `[[wikilinks]]` shown as **pills** — accent when resolved, tertiary when
  dangling, tap to navigate or offer-create, reusing the existing resolver + create flow).
- **Document header:** large `docTitle`, optional emoji/icon slot, a quiet metadata line
  (project · edited · word count). Title still derives frontmatter → first `#` → filename
  (existing `noteTitle` logic).
- **Linked references card:** restyle `BacklinksPanel` as a Craft-style card
  (`Theme.Elevation.card`, snippet rows) rather than the current disclosure row.
- Keep the dirty indicator + `⌘S` semantics.

**Technical approach & risk (called out honestly):** a live editor on macOS 14 needs an
`NSViewRepresentable` wrapping an `NSTextView` (TextKit 2) that applies attributes on each
text change — SwiftUI's `TextEditor` cannot style-as-you-type. The Notes spec already
flagged exactly this (source-mode live highlighting was descoped for the same reason).
The decoration must be **pure and testable**: a new `Logic/NoteDecoration.swift` maps
markdown source → styled ranges + hidden-marker ranges + wikilink ranges (built on
`MarkdownBlocks`/`WikilinkSyntax`), so the `NSTextView` glue stays thin. If 2a proves
heavier than budgeted, the fallback is to keep Preview read-mode and only upgrade its
typography (Phase 1 already does most of that) — but 2a is the goal.

### 2b — Block affordances (higher risk, follows 2a)
- **Block hover-handles:** a left gutter overlay showing `⠿` (drag-to-reorder) and `+`
  (insert) per block, aligned to block ranges from `NoteDecoration`. Reorder rewrites the
  underlying markdown text.
- **`/` slash menu:** typing `/` at line start opens a `Theme.Elevation.pop` popover
  (To-do, Heading, Link to note, Sub-page, "Ask the agent"). Filtering is pure
  (`Logic/SlashMenu.swift`, TDD'd, mirroring `CommandBarEngine`'s item-filter shape).
- **Subpage cards:** a link to another note can render inline as a Craft-style card
  (icon + title + subtitle) via `Theme.Elevation.card`.

**Testing (TDD):** `NoteDecoration` (source → decorations: heading levels, bold/italic/code
ranges, hidden markers, wikilink spans, edge cases) and `SlashMenu` (query → filtered
commands) are pure and fully unit-tested with fixtures. The `NSTextView` representable,
header, gutter, and popover are build + Leon's eye. Existing `MarkdownBlocksTests` /
`WikilinkIndexTests` stay authoritative for parsing.

---

## Phase 3 — Agent-drafted Daily Note (ritual fused)

Turn the transient ritual into a **daily `.md` document the agent drafts overnight**, then
Leon edits like any Craft note (via Phase 2's editor).

**Where it lives (open question — needs Leon's pick):** Mustard has no single global vault
(`SourceSettings.sources` is per-project). Options: (a) a **designated "journal" project**
chosen in Settings (recommended — one clear home, plays with existing project model);
(b) the daily note lives per-active-project; (c) a fixed `~/…/Mustard/daily/`. Proposed:
**(a)**, path `daily/YYYY-MM-DD.md` in the chosen project, frontmatter `type: daily`,
`date:`.

**Composition (pure, TDD'd):** `Logic/DailyNoteComposer.swift` — given `(tasks, recs,
events, day, calendar)` produce the note's markdown:
- **"From your agent overnight"** section — the standup: pending recs (source, confidence,
  title) + output-waiting count, reusing `RitualPlanner.standup`/`RecommendationQueue`
  and `AgentInbox` counts. Rendered as an agent-tinted callout; ritual actions
  (Approve/Snooze) remain available inline via the existing `AgentService.decide`/`snooze`.
- **Rolled over** — `RitualPlanner.rollover` (already stamps `carriedForwardAt`).
- **Today's focus** — `RitualPlanner.focused` (the ⭐ tasks).
- **Calendar** — today's `CalendarEvent`s.
- **Notes** — empty free-write area for Leon.

**Population trigger:** a cheap step in the existing 60s app loop / first-open-of-day
writes the composed file (local, instant — no `claude -p` required). An **optional** agent
enrichment pass (one `claude -p`, subject to `TrustPolicy`) can add a one-line summary —
gated exactly like other agent writes, snapshot-before-write per the Notes safety net; no
silent destruction. `NoteIndexService` picks the file up on its normal reindex.

**Entry points (reuse existing wiring):**
- `TodayView` — the existing "Plan your day" banner and `MorningRitualView` gain an
  "Open today's note" affordance; finishing the ritual (`onFinish`) stamps + opens the note.
- `CommandBarEngine` — a `.openDailyNote` kind (peer to the existing `.planDay`,
  `.goNotes`).
- Notes sidebar — a pinned "Daily" group.

The **wizard is not removed** — decision 6 of the ritual spec (guided flow builds the
habit) still holds; the wizard becomes the fast-path that *writes into* the note, and the
document is what persists, links, and is searchable.

**Data model:** no new `@Model`. The note is a vault file mirrored by the existing
`NoteIndexEntry`; `type: daily` frontmatter is the only marker. This keeps CloudKit-shape
(ADR-0001) intact.

**Testing (TDD):** `DailyNoteComposer` (sections present/omitted by input, ordering,
pinned-UTC-calendar date handling, empty-state lines) with fixtures; `RitualPrompt`
already covers the offer gating. Views build + eye.

---

## Failure / edge behaviour

- **Live editor on a huge note:** decoration runs on change; keep it range-scoped and
  debounced. If a note is pathologically large, fall back to plain text (loadFailed path
  already exists) — never block typing.
- **Daily note edited then re-composed:** the agent writes the file **once per day** (guard
  on existence + `type: daily`), never clobbering Leon's edits mid-day; snapshot-before-write
  covers the race, same net as meeting-sync + note saves.
- **No journal project configured (Phase 3):** the Daily Note affordance shows a calm
  "Pick a journal folder in Settings" state rather than erroring.
- **Ritual never run:** Today behaves exactly as today; the daily note simply isn't created
  until first plan/open (no nags beyond the existing banner).

## Verification (per CLAUDE.md testing rules)

- Pure logic is **TDD, tests first**, pinned UTC `Calendar` + fixtures: `NoteDecoration`,
  `SlashMenu`, `DailyNoteComposer`. `swift test` must stay green (535+ cases today).
- Views are **build + eye**: `swift build` passes; `./build-app.sh` produces a runnable
  app; Leon confirms the editor feel, daily-note population, depth/motion in the real app
  (the in-session shell has no Screen Recording/TCC — the agent cannot screenshot the
  native app and will not claim a view "looks right", only that it builds and runs).
- Each phase is a separate PR behind the required `.agent-loop/checks.yml` gates.

## Decision log — how we got here (this session)

1. Leon: "I really enjoy [Craft] — from the UI to its features; a lot we could pull." →
   catalogued Craft ideas against Mustard's surfaces (tiered ★ now / ◐ later / ○ skip).
2. Leon liked all of it, especially the Daily Note, and asked to fuse it with the morning
   ritual + agent population. → two exploratory HTML mockups on the real tokens.
3. Re-synced to `main`: **Notes Phase A** and the **morning ritual** had already shipped,
   which reframed the work — the Notes editor is a Source/Preview toggle (Phase C parked),
   and the ritual is a transient wizard. Mockups + this spec were rebuilt against that.
4. Leon: "spec up to do everything" → this phased spec covering the whole exploration:
   Theme foundation → surface polish → Craft live editor (Notes Phase C) → agent-drafted
   Daily Note; with dark mode / focus mode / cover images / full-text search explicitly
   recorded as considered-but-deferred.

## Open questions / risks

- **NSTextView live editor (Phase 2)** is the real cost centre and the main schedule risk;
  2a/2b split de-risks it, and Phase 1 already banks most of the read-side polish.
- **Daily Note location (Phase 3)** — needs Leon's pick among the three options above
  (recommended: a designated journal project).
- **Dark mode tension** — Craft's signature adaptive look conflicts with ADR-0005's light
  lock; deferred here rather than quietly breaking the ADR.
- **Agent auto-writing the daily note** — kept local-by-default and behind `TrustPolicy`
  for any `claude -p` enrichment, with snapshot-before-write, to stay inside the
  review/trust philosophy the product is built on.
