# Craft Pass — Phase 0 (Theme foundation) + Phase 1 (Surface polish) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the Craft-warmth groundwork from the 2026-07-06 spec: depth/motion/radius/editorial-type tokens in `Theme` (Phase 0), then apply them to the first surfaces (Phase 1) — markdown-rendered agent output, card depth + hover-lift on board/recommendation cards, reading typography, and warmer empty states — with zero schema change and zero new pure logic.

**Architecture:** Pure token additions to `Logic/Theme.swift` (`Theme.Elevation` + an `.elevation(_:cornerRadius:)` View extension applying background/clip/border/shadow as one unit, `Theme.Motion` animation tokens, `Theme.Metrics` radius scale, editorial `Theme.Fonts`). The existing `MarkdownPreviewView` block renderer is split: a reusable non-scrolling `MarkdownBlocksView(content:resolve:onWikilinkTap:bodyFont:)` plus the thin scroll/padding wrapper the Notes editor keeps. Consumers pass no-op `resolve`/`onWikilinkTap` closures where there is no wikilink graph. Views only re-read tokens — no behaviour or data-layer change.

**Tech Stack:** Swift 5.9 SPM, SwiftUI (macOS 14), SwiftData, XCTest. No new dependencies.

**Backing docs:** `docs/specs/2026-07-06-craft-inspired-notes-and-daily-note-design.md` (read fully before any task — Phases 0 and 1 are the active scope; Phase 2 is a later slice, Phase 3 is pinned).

**Spec drift note (binds Task 3):** the spec's Phase 1 says "markdown-render `OutputCard` content in the console's output-card row" — but `OutputCard` no longer exists. **ADR-0010** removed it: output review now lives on the board's **Needs Review** column, and the reviewable output travels in `MustardTask.notes` (reviewed in `TaskDetailSheet`, whose footer has "Accept output"). The spec's intent — *agent-produced markdown must read as markdown at review time* — therefore lands on the living surfaces: `TaskDetailSheet`'s body preview (block-rendered, reading type) and the board card (elevation). The console keeps its editable draft `TextEditor` untouched (it is an editor, not a reader).

**Conventions that bind every task (CLAUDE.md):**
- Phase 0/1 is **views + declarative tokens** — no new pure logic, so no new tests; the full suite must stay green untouched.
- Views: `swift build` + `swift test` only — never claim views "look right"; Leon confirms in the running app.
- Theme tokens only (`Theme.Palette`/`Theme.Fonts`/`Theme.Elevation`/`Theme.Motion`/`Theme.Metrics`) — no hardcoded colors or durations in views. The dark notch (`NotchSurface.swift`) is the standing exception and is not touched.
- Match surrounding code style and comment density; keep access levels as found (MustardKit views are mostly internal, some public).
- Commits: `type(scope): summary` + the Co-Authored-By trailer, in bite-sized test-passing steps.

**File map:**

| File | Task | Responsibility |
|---|---|---|
| `Sources/MustardKit/Logic/Theme.swift` (modify) | 1 | `Elevation` + `.elevation()` extension, `Motion`, `Metrics`, editorial `Fonts` |
| `Sources/MustardKit/Views/MarkdownPreviewView.swift` (modify) | 2 | extract reusable `MarkdownBlocksView` (+ `bodyFont` param); preview keeps scroll+padding |
| `Sources/MustardKit/Views/TaskDetailSheet.swift` (modify) | 3 | body preview block-renders `task.notes` via `MarkdownBlocksView`, reading type |
| `Sources/MustardKit/Views/MustardBoardCard.swift` (modify) | 4 | `.elevation(.card)` + hover-lift (`.float`, `Theme.Motion.settle`, −1pt offset) |
| `Sources/MustardKit/Views/AgentConsoleView.swift` (modify) | 4 | `RecommendationRow` as elevated card (selection preserved); spacing over dividers; ad-hoc `.snappy` → `Motion.settle` |
| `Sources/MustardKit/Views/TodayView.swift` (modify) | 5, 6 | header `docH1`; warm "Nothing scheduled yet" empty state |
| `Sources/MustardKit/Views/NotesView.swift` (modify) | 6 | warm "Select a note" + sidebar empty states |
| `Sources/MustardKit/Views/BacklinksPanel.swift` (modify) | 6 | warm "No backlinks yet" empty state |

Dependencies: 1 → everything; 2 → 3; 4/5/6 independent after 1.

---

### Task 1: Theme foundation (Phase 0)

**Files:**
- Modify: `Sources/MustardKit/Logic/Theme.swift`

Pure additions — nothing existing changes, so every current surface renders identically until Phase 1 consumes the tokens.

- [x] **Step 1: `Theme.Elevation`** — three shadow recipes as an enum with internal `shadowOpacity`/`shadowRadius`/`shadowY` accessors:
  - `card` — black 5% opacity, radius 14, y 4 (board cards, rec rows, callouts)
  - `float` — black 10% opacity, radius 24, y 10 (hover lift, open-editor feel)
  - `pop` — black 14% opacity, radius 28, y 12 (menus, popovers)
- [x] **Step 2: `.elevation(_:cornerRadius:)`** — a public `View` extension (default radius `Theme.Metrics.rLg`) applying, as one unit: `Theme.Palette.bg` background in a rounded rect, matching `clipShape`, 0.5pt `hairline` stroke overlay, and the level's `.shadow(color:radius:x:y:)`. One recipe so a surface can swap levels (card → float on hover) without re-deriving any part.
- [x] **Step 3: `Theme.Motion`** — `settle = .snappy(duration: 0.16)`, `expand = .snappy(duration: 0.18)`, `pop = .spring(duration: 0.22)`. (All macOS 14 APIs.)
- [x] **Step 4: `Theme.Metrics`** — radius scale codifying hand-used values: `rSm 6`, `rMd 7`, `rLg 10`, `rXl 12`.
- [x] **Step 5: `Theme.Fonts` editorial additions** — `docTitle` (33 semibold), `docH1` (22 semibold), `docH2` (18 semibold), `reading` (16 regular). Existing tokens untouched.
- [ ] **Step 6:** `swift build` + full `swift test` → green (declarative values; verified by build + the Phase 1 surfaces). **Commit** — `feat(theme): elevation/motion/metrics/editorial tokens (craft pass phase 0)`

---

### Task 2: Extract `MarkdownBlocksView`

**Files:**
- Modify: `Sources/MustardKit/Views/MarkdownPreviewView.swift`

- [x] **Step 1:** Move the block-stack body (LazyVStack of `MarkdownBlocks.parse` blocks, the block renderers, the wikilink URL scheme helpers, `flowingText`) into a new internal `MarkdownBlocksView` in the same file, with an optional `bodyFont: Font = Theme.Fonts.body` applied to paragraph/bullet/ordered/quote runs (headings/code keep their own sizes). The `openURL` wikilink interception travels with it so every consumer gets tap handling.
- [x] **Step 2:** `MarkdownPreviewView` becomes the thin wrapper: `ScrollView { MarkdownBlocksView(...).padding(28) }.background(Theme.Palette.bg)` — the Notes editor renders pixel-identically.
- [ ] **Step 3:** `swift build` + full suite → green. **Commit** — `refactor(notes): extract reusable MarkdownBlocksView from the preview (craft pass phase 1)`

---

### Task 3: Markdown-render agent output at review time

**Files:**
- Modify: `Sources/MustardKit/Views/TaskDetailSheet.swift`

Per the spec-drift note: `OutputCard` is gone (ADR-0010); the reviewable output is `task.notes` on a Needs Review board task, read in this sheet's BODY section — today an inline-only `AttributedString` that leaves headings/bullets raw.

- [x] **Step 1:** In `bodySection`, replace the preview-mode `Text(markdownBody)` with `MarkdownBlocksView(content: task.notes, resolve: { _ in nil }, onWikilinkTap: { _ in }, bodyFont: Theme.Fonts.reading)` (no wikilink graph here). Keep the edit/preview segmented control exactly as is — edit mode still binds the raw markdown, so there is no nested-layout surprise and no lost editability.
- [x] **Step 2:** Delete the now-unused `markdownBody` helper.
- [ ] **Step 3:** `swift build` + full suite → green. **Commit** — `feat(review): block-render agent output markdown in the task sheet (craft pass phase 1)`

---

### Task 4: Card depth + hover-lift

**Files:**
- Modify: `Sources/MustardKit/Views/MustardBoardCard.swift`
- Modify: `Sources/MustardKit/Views/AgentConsoleView.swift`

- [x] **Step 1: Board card.** Replace the hand-rolled background/stroke/clip trio with the accent-border overlay followed by `.elevation(hovering ? .float : .card, cornerRadius: 9)` (radius 9 preserved exactly), a `-1pt` `.offset` lift on hover (no layout shift), and `.animation(Theme.Motion.settle, value: hovering)`. The existing `hovering` state already drives the owner toggle and gate actions — those reveals now settle with the same motion token (one feel; deliberate).
- [x] **Step 2: Recommendation rows.** In `RecommendationRow`, keep the selection tint + leading accent bar exactly as-is and add `.elevation(.card, cornerRadius: Theme.Metrics.rLg)` beneath them. In the master list, drop the per-row hairline `Divider`s (an elevated bordered card next to a divider reads as a double line) in favour of 8pt bottom padding per row.
- [x] **Step 3: Motion token.** Swap `SourceGroupHeader`'s ad-hoc `withAnimation(.snappy(duration: 0.15))` for `Theme.Motion.settle` (spec: one canonical feel; 0.15 → 0.16 is imperceptible).
- [ ] **Step 4:** `swift build` + full suite → green. **Commit** — `feat(console,board): card elevation + hover lift via theme tokens (craft pass phase 1)`

---

### Task 5: Reading typography

**Files:**
- Modify: `Sources/MustardKit/Views/TodayView.swift` (header)
- (Output reading type ships with Task 3's `bodyFont: .reading`.)

- [x] **Step 1:** Today's header `Text("Today")` moves `Theme.Fonts.header` (22 medium) → `Theme.Fonts.docH1` (22 semibold) — same size, weight only, so the `firstTextBaseline` row layout is undisturbed. Nothing else in the header row changes.
- [ ] **Step 2:** `swift build` + full suite → green. Fold into Task 6's commit.

---

### Task 6: Warmer empty states

**Files:**
- Modify: `Sources/MustardKit/Views/TodayView.swift`
- Modify: `Sources/MustardKit/Views/NotesView.swift`
- Modify: `Sources/MustardKit/Views/BacklinksPanel.swift`

Pattern (mirrors the console's existing `detailEmpty`): centered tertiary SF Symbol glyph + the existing line; at most one short invitation; tokens only.

- [x] **Step 1: Today** — "Nothing scheduled yet" becomes a centered `sun.max` glyph + the existing line + one invitation ("Capture a task below to start the day"), sitting right above the quick-capture field it points at.
- [x] **Step 2: Notes detail** — "Select a note" gains a centered `doc.text` glyph above the existing line.
- [x] **Step 3: Notes sidebar** — `emptyState(_:)` gains a `symbol:` parameter; the two callers pass `folder.badge.plus` (no sources) and `doc.text.magnifyingglass` (nothing indexed).
- [x] **Step 4: Backlinks** — "No backlinks yet" becomes a centered `link` glyph + the existing line, centered in the disclosure content.
- [ ] **Step 5:** `swift build` + full suite → green. **Commit** — `feat(views): docH1 today header + warmer empty states (craft pass phase 1)`

---

### Task 7: Finish line

- [ ] Full `swift test` + `swift build` (CI/macOS — the build box is Linux, so verification is CI's job) + `./build-app.sh`; Leon eye-checks depth, motion, markdown output, and empty states in the running app.
- [ ] `docs/build-order.md`: no in-progress section exists (Done ✅ / Next ⛔ / cleared 🟢 / Later 🔓 / Ideas 💡) — append an F-entry to **Done** only once merged and Leon-confirmed; skipped at build time by design.
- [ ] PR to main: `feat(theme): craft pass phases 0–1 — tokens + surface polish`; fresh-context review per `.agent-loop/review-rubric.md`; risk expected LOW/MEDIUM (Sources/ views + one Logic token file, no schema, no gated actions).

## Self-review notes

- Spec coverage: Phase 0 tokens → T1 (all four token families, values from the spec's recipes); Phase 1 markdown output → T2+T3 (adapted to ADR-0010 — drift note documents why the console's output-card row cannot exist); card depth/hover → T4; reading type → T3+T5; empty states → T6.
- The `.elevation` recipe hardcodes `Theme.Palette.bg` as the card ground — every surface it's applied to in this pass already used `bg`; a `background:` parameter can be added the day a non-bg card needs depth (YAGNI).
- Deliberate simplifications: Today's date-line task-count enrichment skipped (spec offered it as the fallback if the header change disturbed layout — it doesn't); recommendation-list dividers → spacing is the one visual change not literally named by the spec, forced by border-on-border.
- Risk points for CI: `Animation.snappy(duration:)` / `Animation.spring(duration:)` are macOS 14-only (package minimum is macOS 14 — fine); `.elevation` being a `public` extension on `View` referencing internal enum accessors is legal (not `@inlinable`).
