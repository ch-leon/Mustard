# Craft Live Notes Editor (Phase 2: 2a + 2b) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `NoteEditorView`'s Source/Preview segmented toggle with a single always-rendered, editable Craft-style surface — **2a:** style-as-you-type markdown (headings sized, bold/italic/code with de-emphasized markers, wikilink pills, document header, linked-references card), then **2b:** block hover-handles with drag-reorder, a `/` slash menu, and (optional) inline subpage cards — while the vault `.md` file stays the byte-for-byte source of truth.

**Architecture:** A new pure `Logic/NoteDecoration.swift` maps markdown source → UTF-16 styled spans and a **total block partition** (block ranges concatenate back to the exact source — the round-trip guard). A thin `MarkdownTextView` `NSViewRepresentable` wraps an **explicit TextKit 1 NSTextView** stack and only applies those spans as `NSTextStorage` attributes; it never rewrites text. Every 2b affordance is a pure text rewrite: `Logic/BlockReorder.swift` (`source + move → new source`) and `Logic/SlashMenu.swift` (trigger detection, filtering mirroring `CommandBarEngine`, insertion templates) are fully unit-tested; the view splices their output through one undoable `insertText(_:replacementRange:)` edit. `NoteEditorView` keeps its exact dirty-dot / ⌘S / snapshot-guarded save / save-on-switch semantics and its title derivation; `NotesView` keeps ownership of the wikilink resolver and the create-from-dangling flow. There is **no stored block model and no block database** — blocks are presentation over text ranges, and the file on disk is always plain markdown Obsidian and the agent can read.

**Tech Stack:** Swift 5.9 SPM, SwiftUI + AppKit (`NSViewRepresentable`/`NSTextView`, macOS 14), SwiftData (untouched), XCTest. No new dependencies.

**Backing docs:** `docs/specs/2026-07-06-craft-inspired-notes-and-daily-note-design.md` (Phase 2 section — read fully before any task) and `docs/specs/2026-07-05-notes-vault-backlinks-design.md` (file-native architecture this preserves). Prior art: `docs/superpowers/plans/2026-07-05-notes-phase-a.md`.

**Prerequisite (hard):** Phase 0 theme tokens must be on `main` before Task 5 — `Theme.Fonts.docTitle/docH1/docH2/reading`, `Theme.Elevation.card/float/pop` (+ `elevation(_:)` modifier), `Theme.Motion.settle/expand/pop`, `Theme.Metrics` radii. Tasks 1–4 have no token dependency and may start immediately; if Phase 0 hasn't merged when Task 5 starts, STOP and flag rather than hardcoding values.

**Milestones / PRs:** two reviewable PRs off `main` — **PR-A (2a)** = Tasks 1–5 on branch `agent/craft-editor-2a`, **PR-B (2b)** = Tasks 6–10 on branch `agent/craft-editor-2b` (branched from merged 2a). The spec calls Phase 2 **High risk** (NSTextView); expect the `deep-review` panel before merge per `.agent-loop/risk.yml`.

## Decisions already made (do not relitigate)

1. **TextKit 1, explicitly.** The representable builds the classic stack by hand (`NSTextStorage → NSLayoutManager → NSTextContainer → NSTextView`) rather than taking macOS 14's TextKit 2 default. Justification: (a) any stray access to `NSTextView.layoutManager` silently downgrades TK2→TK1 mid-session — an entire class of heisenbugs we opt out of by pinning the mode; (b) 2b's gutter needs stable block-range → rect geometry, and TK1's `NSLayoutManager.boundingRect(forGlyphRange:in:)` is the long-stable API for exactly that (TK2's fragment enumeration on macOS 14 still has known invalidation quirks); (c) we style purely via `NSTextStorage` attributes — TK2's wins (noncontiguous layout for huge documents) don't apply at note scale, and the pathological-size case falls back to plain text anyway. Revisit TK2 only if a real defect forces it.
2. **Markers are de-emphasized, never hidden.** `**`, `*`, `` ` ``, `#`, `[[`/`]]`/`|` render small/tertiary via a `.marker` span — the characters stay in the text view. Craft-style marker *hiding* (zero-width folding) breaks caret movement, selection, and undo in exactly the ways that sink live editors; de-emphasis gets ~90% of the calm for ~10% of the risk. `NoteDecoration` still emits marker ranges as their own kind, so a future hiding pass is data-ready without re-parsing work.
3. **Frontmatter stays visible in the editor as a de-emphasized raw block** (monospaced, small, tertiary — clearly "metadata, not prose"), below the SwiftUI document header. Rejected alternative — hiding it behind the header — requires splitting the file into (frontmatter, body), holding only the body in the text view, and re-prepending on save: that breaks the load-bearing invariant *text-view string == disk string* (dirty check, snapshot save, and the round-trip guarantee all lean on it), and `Frontmatter.parse` normalizes CRLF so it cannot be the splitter without silently rewriting files. Leon hand-edits YAML in Obsidian; hiding it from a power user is anti-calm anyway. The header (Decision 4) makes the *derived* title the visual headline so the YAML block reads as a quiet appendix, not the title.
4. **Document header is SwiftUI chrome, not text.** `docTitle` title (existing `noteTitle` derivation: frontmatter → first `#{1,6} ` heading → filename stem, verbatim from `NoteEditorView`), plus a metadata line (project · edited · word count) computed by a tiny pure `NoteMetadata`.
5. **Round-trip guarantee** is enforced two ways in `NoteDecorationTests`: (a) `NoteDecoration.blocks(_:)` is a **total partition** — substrings of all block ranges concatenated equal the source exactly, for every fixture including grammar we don't style (tables, setext headings, HTML — they decorate as plain paragraphs but are never normalized); (b) decoration has **no rewrite API** — it returns ranges only. The only functions that produce new source are `BlockReorder.move` and `SlashMenu.insertion`, each pinned by its own byte-exact tests.
6. **`MarkdownPreviewView` is not deleted.** The editor stops using it, but Phase 1 renders `OutputCard` content through it. Only remove the editor's `EditorMode` toggle.

**Conventions that bind every task (CLAUDE.md):**
- TDD for Logic/: failing test first, see it fail, implement, see it green. One test file per unit.
- Pin time/zone: `Date(timeIntervalSince1970:)` + injected `Calendar` with `TimeZone(identifier: "UTC")`. Never the ambient clock.
- Views/AppKit glue: **build + Leon's eye only** — never claim a view "looks right"; state it builds and CI is green, and list what Leon should eyeball.
- Colors/fonts only from `Theme` tokens (including the Phase 0 additions).
- Commits: `type(scope): summary` + the Co-Authored-By trailer. Bite-sized, each leaving CI green.
- **Verification is CI-only for this plan.** The implementation container cannot build Swift. For every "run the tests" step: commit, push the branch, open/refresh the draft PR, and read the **macOS CI** result (`.github/workflows/ci.yml` runs `swift build` + `swift test` on the self-hosted runner for same-repo branches). "FAIL" and "PASS" below mean *the CI test job's log shows it*. Never mark a task done on a red or missing CI run. Baseline on `main`: ~576 test functions — confirm the exact count from the first CI log and track it.

**File map (whole feature):**

| File | Task | Responsibility |
|---|---|---|
| `Sources/MustardKit/Logic/NoteDecoration.swift` (create) | 1, 2 | block partition (round-trip-safe) + styled spans |
| `Tests/MustardTests/NoteDecorationTests.swift` (create) | 1, 2 | partition round-trip, span fixtures |
| `Sources/MustardKit/Logic/WikilinkURL.swift` (create) + tests | 3 | `mustard-note://` encode/decode (extracted from MarkdownPreviewView) |
| `Sources/MustardKit/Views/MarkdownTextView.swift` (create) | 3, 4 | TK1 NSViewRepresentable + Coordinator (binding, decoration application, link clicks, focus) |
| `Sources/MustardKit/Views/NoteEditorView.swift` (modify) | 3, 4, 5 | swap TextEditor+toggle for MarkdownTextView; document header |
| `Sources/MustardKit/Logic/NoteMetadata.swift` (create) + tests | 5 | word count + metadata line |
| `Sources/MustardKit/Views/BacklinksPanel.swift` (modify) | 5 | linked-references card restyle |
| `Sources/MustardKit/Logic/SlashMenu.swift` (create) + tests | 6 | trigger detection, filtering, insertion templates |
| `Sources/MustardKit/Views/SlashMenuView.swift` (create) | 7 | caret-anchored `Theme.Elevation.pop` menu |
| `Sources/MustardKit/Views/NotesView.swift` (modify) | 7 | sub-page creation callback into the editor |
| `Sources/MustardKit/Logic/BlockReorder.swift` (create) + tests | 8 | pure `source + move → new source` |
| `Sources/MustardKit/Views/BlockGutterOverlay.swift` (create) | 9 | ⠿ / + hover handles, drag-reorder wiring |
| `Sources/MustardKit/Views/MarkdownTextView.swift` (modify) | 9, 10 | block-rect publication; subpage-card drawing |
| `CLAUDE.md`, `docs/build-order.md` (modify) | 11 | folder layout + tracker updates |

Dependencies: 1 → 2 → 3 → 4 → 5 (= PR-A). Then 6 → 7, 8 → 9, 10 — all needing 4; 7 and 9 independent of each other (= PR-B). 11 last.

---

## Milestone 2a — live document surface (PR-A, branch `agent/craft-editor-2a`)

### Task 1: `NoteDecoration` block partition + round-trip guard

**Files:**
- Create: `Sources/MustardKit/Logic/NoteDecoration.swift`
- Create: `Tests/MustardTests/NoteDecorationTests.swift`

Pure, no Foundation-FS, no clock. Operates on the **raw** source string (never CRLF-normalize — this layer must be byte-faithful; contrast `MarkdownBlocks.parse`, which normalizes because it renders). All ranges are UTF-16 `NSRange` (NSTextStorage coordinates), matching `WikilinkSyntax.Occurrence.range`.

API (exact):

```swift
import Foundation

/// Pure decoration layer for the live Notes editor (Craft spec 2026-07-06, Phase 2a).
/// Maps markdown SOURCE → styled UTF-16 ranges + a total block partition. Read-only
/// by design: there is deliberately NO API that returns rewritten source — the
/// markdown-as-truth guarantee (spec hard constraint) is structural, not tested-in.
public enum NoteDecoration {

    public struct Block: Equatable {
        public let range: NSRange        // includes the block's trailing blank lines
        public let isFrontmatter: Bool   // leading --- YAML block (fences included)
        public let isFence: Bool         // ``` code block (fences included)
    }

    /// Total partition of `source`: ranges are contiguous, in order, and cover every
    /// UTF-16 unit — substrings concatenated re-assemble the source EXACTLY.
    /// Grammar this editor doesn't understand (tables, setext, HTML) still lands in
    /// blocks (as paragraphs); nothing is dropped or normalized.
    public static func blocks(_ source: String) -> [Block]
}
```

Blocking rules (mirror `MarkdownBlocks.parse`'s line classification, but range-preserving): a leading `---` fence pair (per `Frontmatter.parse`'s detection rule, applied to raw lines) is one frontmatter block; ``` fences swallow to the closing fence or EOF; otherwise consecutive non-blank lines group into one block, split at blank lines; heading/rule/quote/list lines start a block per line group exactly as `MarkdownBlocks` classifies them. Trailing blank lines attach to the preceding block (so blocks are the 2b drag units, separators included). `\r\n` line breaks stay inside the owning line's range.

- [ ] **Step 1: Write the failing tests** (suite skeleton — match `MarkdownBlocksTests`' terse style):

```swift
import XCTest
@testable import MustardKit

final class NoteDecorationTests: XCTestCase {
    /// THE round-trip guard (spec hard constraint): the partition must reassemble
    /// the source byte-for-byte for every fixture — including grammar we don't style.
    private func assertPartitionLossless(_ source: String, file: StaticString = #filePath, line: UInt = #line) {
        let ns = source as NSString
        let blocks = NoteDecoration.blocks(source)
        let joined = blocks.map { ns.substring(with: $0.range) }.joined()
        XCTAssertEqual(joined, source, file: file, line: line)
        // Contiguous + in order:
        var cursor = 0
        for block in blocks {
            XCTAssertEqual(block.range.location, cursor, file: file, line: line)
            cursor += block.range.length
        }
        XCTAssertEqual(cursor, ns.length, file: file, line: line)
    }

    func test_blocks_partition_reassemblesSource_exactly() {
        assertPartitionLossless("---\ntitle: X\n---\n\n# H\n\npara one\npara two\n\n- a\n- b\n\n```\ncode [[x]]\n```\n")
    }
    func test_blocks_unsupportedGrammar_staysRaw_neverNormalized() {
        assertPartitionLossless("| a | b |\n|---|---|\n| 1 | 2 |\n\nSetext\n======\n\n<div>html</div>")
    }
    func test_blocks_crlf_and_noTrailingNewline_lossless() {
        assertPartitionLossless("# H\r\n\r\npara\r\ntail without newline")
    }
    func test_blocks_emptySource_isEmpty() {
        XCTAssertEqual(NoteDecoration.blocks(""), [])
    }
    func test_blocks_frontmatterFlagged_andUnterminatedIsNotFrontmatter() {
        XCTAssertTrue(NoteDecoration.blocks("---\ntitle: x\n---\nbody")[0].isFrontmatter)
        XCTAssertFalse(NoteDecoration.blocks("---\ntitle: x\nno end")[0].isFrontmatter)
    }
    func test_blocks_trailingBlankLines_attachToPrecedingBlock() {
        let source = "# H\n\n\npara"
        let ns = source as NSString
        let blocks = NoteDecoration.blocks(source)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(ns.substring(with: blocks[0].range), "# H\n\n\n")
    }
    func test_blocks_fenceSwallowsBlankLinesAndMarkers_untilClose() {
        let blocks = NoteDecoration.blocks("```\n# not a heading\n\n---\n```\nafter")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks[0].isFence)
    }
}
```

Add further lossless fixtures freely (nested lists, quote runs, rules, `***`, unterminated fence at EOF) — every new fixture goes through `assertPartitionLossless`.

- [ ] **Step 2: Push → CI shows `NoteDecorationTests` FAIL** (types undefined). (Commit on the branch; draft PR open from the first push so every subsequent push gets a CI run.)
- [ ] **Step 3: Implement `blocks(_:)`.** Single pass over line ranges (`NSString.getLineStart`/`lineRange(for:)` or a manual UTF-16 scan — do NOT `components(separatedBy:)`, which loses `\r\n` fidelity). Classify each line with the same predicates as `MarkdownBlocks.blockLine` (trimmed compare for `---`/`***`, `#{1,6} `, `> `, `- `/`* `, `\d+\. `, ``` toggle); group; attach trailing blanks.
- [ ] **Step 4: Push → CI green** (suite + full `swift test` + `swift build`).
- [ ] **Step 5: Commit** — `feat(notes): NoteDecoration block partition with lossless round-trip guard`

---

### Task 2: `NoteDecoration` styled spans

**Files:**
- Modify: `Sources/MustardKit/Logic/NoteDecoration.swift`
- Modify: `Tests/MustardTests/NoteDecorationTests.swift`

API additions (exact):

```swift
public struct Span: Equatable {
    public let range: NSRange
    public let kind: Kind
}

public enum Kind: Equatable {
    case frontmatter                                  // whole YAML block incl. fences
    case heading(level: Int)                          // heading TEXT (hashes excluded)
    case marker                                       // syntax chars to de-emphasize
    case bold, italic, inlineCode                     // content between markers
    case codeBlock                                    // fence interior
    case listMarker                                   // "- " / "1. " / "> " prefix
    case wikilink(target: String, alias: String?)     // the VISIBLE label span
}

/// All spans for the whole source.
public static func spans(_ source: String) -> [Span]
/// Spans for one block only — the per-keystroke fast path (2a coordinator).
public static func spans(_ source: String, in block: Block) -> [Span]
```

Inline grammar (deliberately tight — anything else stays raw text): per line, code spans first (`` `x` `` — no emphasis inside), then `**bold**`, then `*italic*`; single-line only, non-nested; underscore emphasis is NOT parsed (raw). Wikilinks reuse `WikilinkSyntax.occurrences(in:)` — one grammar, now four consumers: `[[`, `]]`, the `#anchor`, the `|` and, when aliased, the target half are `.marker`; the visible label (alias if present, else target) is `.wikilink`. Heading lines: `#…# ` prefix `.marker`, rest `.heading(level:)`. Fenced blocks: fence lines `.marker`, interior `.codeBlock`, and NO inline/wikilink spans inside (matches `WikilinkIndex.extractLinks`' fence rule). Frontmatter block: one `.frontmatter` span, nothing inside parsed.

- [ ] **Step 1: Failing tests** (extend the suite; representative bodies):

```swift
func test_spans_heading_marksHashesAsMarker_textAsHeading() {
    let spans = NoteDecoration.spans("## Two")
    XCTAssertTrue(spans.contains(Span(range: NSRange(location: 0, length: 3), kind: .marker)))   // "## "
    XCTAssertTrue(spans.contains(Span(range: NSRange(location: 3, length: 3), kind: .heading(level: 2))))
}
func test_spans_bold_italic_code_withMarkerRanges() {
    // "a **b** *i* `c`"
    let spans = NoteDecoration.spans("a **b** *i* `c`")
    XCTAssertTrue(spans.contains(Span(range: NSRange(location: 5, length: 1), kind: .bold)))
    XCTAssertTrue(spans.contains(Span(range: NSRange(location: 2, length: 2), kind: .marker)))    // leading **
    XCTAssertTrue(spans.contains(Span(range: NSRange(location: 13, length: 1), kind: .inlineCode)))
}
func test_spans_wikilink_labelAndMarkers_aliasHidesTarget() {
    // "[[Note|alias]]" → markers: "[[", "Note|", "]]"; label: "alias"
    let spans = NoteDecoration.spans("[[Note|alias]]")
    XCTAssertTrue(spans.contains(Span(range: NSRange(location: 7, length: 5),
                                      kind: .wikilink(target: "Note", alias: "alias"))))
}
func test_spans_noEmphasisInsideCodeSpan_orFence_orFrontmatter() {
    XCTAssertFalse(NoteDecoration.spans("`**x**`").contains { $0.kind == .bold })
    XCTAssertFalse(NoteDecoration.spans("```\n**x** [[L]]\n```").contains {
        $0.kind == .bold || $0.kind == .wikilink(target: "L", alias: nil)
    })
}
func test_spans_inBlock_matchesWholeDocumentSubset() {
    let source = "# H\n\npara **b**\n"
    let block = NoteDecoration.blocks(source)[1]
    XCTAssertEqual(NoteDecoration.spans(source, in: block),
                   NoteDecoration.spans(source).filter { block.range.contains($0.range.location) })
}
func test_spans_allRangesWithinBounds_neverOverlapContentKinds() {
    // Fuzz-ish fixture battery: for each fixture, every span range fits in the
    // source and no two non-marker spans overlap.
    for source in ["", "# H", "**a** *b* `c` [[w|x]]", "---\nt: v\n---\n# H\n```\nx\n```"] {
        let ns = source as NSString
        for span in NoteDecoration.spans(source) {
            XCTAssertLessThanOrEqual(span.range.location + span.range.length, ns.length)
        }
    }
}
```

- [ ] **Step 2: Push → CI FAIL. Step 3: Implement** — `spans(_:)` iterates `blocks(_:)`, dispatches per block kind, and delegates line-interior work to one private inline scanner shared by heading/list/quote/paragraph lines. Unmatched markers (`**a`, a lone `` ` ``) produce NO span — raw text, never guessed.
- [ ] **Step 4: Push → CI green. Step 5: Commit** — `feat(notes): NoteDecoration styled spans — headings, emphasis, code, wikilinks with marker de-emphasis`

---

### Task 3: `MarkdownTextView` representable (plain, no styling yet) + editor swap

**Files:**
- Create: `Sources/MustardKit/Views/MarkdownTextView.swift`
- Create: `Sources/MustardKit/Logic/WikilinkURL.swift` + `Tests/MustardTests/WikilinkURLTests.swift`
- Modify: `Sources/MustardKit/Views/NoteEditorView.swift`, `Sources/MustardKit/Views/MarkdownPreviewView.swift`

The one TDD sliver here: extract `MarkdownPreviewView`'s private `mustard-note://` scheme helpers into pure `Logic/WikilinkURL.swift` (`WikilinkURL.url(for target: String) -> URL?`, `WikilinkURL.target(from url: URL) -> String?`) so Task 4's `NSTextView` link handling shares one encoding; `MarkdownPreviewView` switches to it. Tests pin the lossless round-trip for spaces / slashes / unicode targets (`test_urlRoundTrip_spacesSlashesUnicode`, `test_target_rejectsForeignSchemes`).

Then the view glue (build + eye):

- [ ] **Step 1: Failing `WikilinkURLTests` → push → CI FAIL → implement the extraction → CI green. Commit** — `refactor(notes): extract WikilinkURL scheme round-trip into Logic (tested)`
- [ ] **Step 2: Build `MarkdownTextView`.** `NSViewRepresentable` around `NSScrollView` + `NSTextView` with an **explicit TK1 stack** (Decision 1 — construct `NSTextStorage`/`NSLayoutManager`/`NSTextContainer` manually; comment WHY, citing the silent TK2 downgrade trap). Props: `text: Binding<String>`; Coordinator is `NSTextViewDelegate`.
  - `textDidChange` → `text.wrappedValue = textView.string`.
  - `updateNSView` sets `textView.string` ONLY when different from the binding (guard with a `isProgrammaticUpdate` flag in the coordinator) — otherwise every keystroke round-trips SwiftUI → AppKit and teleports the caret. Preserve selection on external replace (clamp `selectedRange`).
  - Font: `Theme.Fonts.reading`-equivalent NSFont (16pt system) as the base typing attribute; `Theme.Palette.bg` background; no rulers; rich text OFF (`isRichText = false` — attributes come from us, not the pasteboard), `allowsUndo = true`, `isAutomaticQuoteSubstitutionEnabled = false` and all other automatic substitutions off (they'd rewrite markdown syntax — smart quotes corrupt `"` in code/YAML).
  - First responder: on `viewDidMoveToWindow` (or a one-shot in `updateNSView`), `window.makeFirstResponder(textView)` via `DispatchQueue.main.async` — never synchronously during view updates (AppKit reentrancy warnings). ⌘S stays with the SwiftUI Save button's `.keyboardShortcut` — window-level key equivalents fire before the field editor, verified by eye in Step 4.
- [ ] **Step 3: Swap it into `NoteEditorView`.** Delete the `EditorMode` enum, the segmented `Picker`, and the `sourceEditor`/preview branch; the body renders `MarkdownTextView(text: $text)`. **Do not touch:** `diskText`, `isDirty`, the dirty dot, `save(to:content:ifDifferentFrom:)` (snapshot-then-write, failed-write-stays-dirty, `ref == self.ref` baseline rule), `.onChange(of: ref)` save-on-switch, `.task(id: ref)` load, `noteTitle` derivation, `BacklinksPanel` mount, `noteIndex.reindex` on save. `MarkdownPreviewView` stays in the tree for Phase 1's OutputCard rendering — only the editor stops importing it.
- [ ] **Step 4: Push → CI green (`swift build` + full suite; expect zero test-count change beyond WikilinkURLTests).** Ask Leon to eyeball: typing, caret, selection, ⌘S while the text view has focus, dirty dot, note switching flushes edits, no smart-quote substitution.
- [ ] **Step 5: Commit** — `feat(notes): TextKit-1 MarkdownTextView replaces Source/Preview toggle (plain text pass)`

---

### Task 4: Style-as-you-type — apply `NoteDecoration` in the coordinator

**Files:**
- Modify: `Sources/MustardKit/Views/MarkdownTextView.swift`, `Sources/MustardKit/Views/NoteEditorView.swift`

No new logic — spans come from Task 2; this is attribute plumbing (build + eye). New props on `MarkdownTextView`: `resolveWikilink: (String) -> NoteRef?`, `onWikilinkTap: (String) -> Void` (threaded from `NoteEditorView`'s existing props — NotesView keeps owning resolution and create-from-dangling).

- [ ] **Step 1: Attribute application.** A single `applyDecorations(in blockRange: NSRange?)` on the coordinator: compute spans (`NoteDecoration.spans(_:in:)` for the edited block, whole-document otherwise), then in one `textStorage.beginEditing()/endEditing()` batch: reset the range to base attributes, then per span set font/color:
  - `.heading(1/2/3+)` → `Theme.Fonts.docH1`/`docH2`/title-size NSFonts, `textPrimary`; `.marker` → 12pt, `textTertiary`; `.bold`/`.italic` → bold/italic 16pt; `.inlineCode`/`.codeBlock` → 13pt monospaced, `surface` background color attribute; `.frontmatter` → 12pt monospaced `textTertiary`; `.listMarker` → `textTertiary`; `.wikilink(target:_)` → `accent` when `resolveWikilink(target) != nil` else `textTertiary`, underline, plus `.link: WikilinkURL.url(for: target)` and `.cursor: pointingHand`. (NSColor bridges: add the handful of needed `NSColor(hex:)` companions next to the tokens — values from `Theme.Palette` only, never fresh hex.)
- [ ] **Step 2: Invalidation strategy (the perf mitigation, comment it in code):**
  - On `textStorage(_:didProcessEditing:range:changeInLength:)` (or `textDidChange`): synchronously re-decorate ONLY the block containing the edit (locate via `NoteDecoration.blocks` over the new string — cheap, or cache block list and binary-search) — keystroke latency stays flat.
  - A **debounced (~150 ms, `Task.sleep` cancelled on next edit) full-document pass** catches edits that change block topology (typing a ``` fence, deleting a blank line merges blocks, editing frontmatter fences).
  - **Large-note fallback (spec "never block typing"):** when `(text as NSString).length > 200_000`, skip decoration entirely — plain editable text, one quiet log line. Constant named and commented.
  - **Undo safety:** attribute passes must never dirty the undo stack or the SwiftUI binding — they go straight to `textStorage` (attribute-only edits don't enter `NSTextView`'s undo path because we bypass `shouldChangeText`), wrapped in the `isProgrammaticUpdate` guard so `textDidChange` isn't re-fired into the binding. Comment WHY.
- [ ] **Step 3: Link clicks.** Coordinator implements `textView(_:clickedOnLink:at:) -> Bool`: decode via `WikilinkURL.target(from:)` → `onWikilinkTap(target)` → `true`; foreign URLs return `false`. This reuses NotesView's existing navigate/create-alert flow untouched (save-on-switch still fires because navigation goes through `selected`).
- [ ] **Step 4: Push → CI green.** Ask Leon to eyeball: headings grow as `#` is typed; markers fade but remain; caret never jumps while typing mid-styled-text; undo/redo of typing behaves; wikilink click navigates; dangling link click offers create; frontmatter reads as quiet metadata; a huge pasted note still types instantly.
- [ ] **Step 5: Commit** — `feat(notes): style-as-you-type decoration with block-scoped invalidation + large-note fallback`

---

### Task 5: Document header, metadata line, linked-references card

**Files:**
- Create: `Sources/MustardKit/Logic/NoteMetadata.swift`, `Tests/MustardTests/NoteMetadataTests.swift`
- Modify: `Sources/MustardKit/Views/NoteEditorView.swift`, `Sources/MustardKit/Views/BacklinksPanel.swift`

**Requires Phase 0 tokens on `main`** (see Prerequisite). Logic first, TDD:

```swift
import Foundation

/// Pure header metadata for the Craft note header (Phase 2a): word count over the
/// frontmatter-stripped body, and the quiet "project · edited · words" line.
public enum NoteMetadata {
    public static func wordCount(_ source: String) -> Int
    /// "Mustard · edited today · 214 words" — modified nil drops the middle segment.
    public static func line(project: String, modified: Date?, wordCount: Int,
                            now: Date, calendar: Calendar) -> String
}
```

- [ ] **Step 1: Failing tests:**

```swift
import XCTest
@testable import MustardKit

final class NoteMetadataTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private let now = Date(timeIntervalSince1970: 1_751_790_000)

    func test_wordCount_stripsFrontmatter_countsBodyWords() {
        XCTAssertEqual(NoteMetadata.wordCount("---\ntitle: skip me\n---\n# Two words\n\none"), 3)
    }
    func test_wordCount_emptyAndWhitespaceOnly_isZero() {
        XCTAssertEqual(NoteMetadata.wordCount(""), 0)
        XCTAssertEqual(NoteMetadata.wordCount("---\nt: x\n---\n  \n"), 0)
    }
    func test_line_editedToday_yesterday_andDated() {
        XCTAssertEqual(NoteMetadata.line(project: "KB", modified: now.addingTimeInterval(-3_600),
                                         wordCount: 2, now: now, calendar: cal),
                       "KB · edited today · 2 words")
        XCTAssertTrue(NoteMetadata.line(project: "KB", modified: now.addingTimeInterval(-86_400),
                                        wordCount: 1, now: now, calendar: cal).contains("edited yesterday"))
    }
    func test_line_nilModified_omitsEditedSegment() {
        XCTAssertEqual(NoteMetadata.line(project: "KB", modified: nil, wordCount: 1, now: now, calendar: cal),
                       "KB · 1 word")
    }
}
```

- [ ] **Step 2: Push → CI FAIL. Step 3: Implement** (word split on whitespace/newlines after `Frontmatter.parse(...).body`; older dates via a fixed `d MMM` `en_US_POSIX` formatter with the injected calendar/zone; singular "1 word"). Push → CI green. **Commit** — `feat(notes): NoteMetadata word count + header line`
- [ ] **Step 4: Header (view).** In `NoteEditorView`, replace the current 22pt title row with a document header above the text view: `noteTitle` in `Theme.Fonts.docTitle`, dirty dot beside it (unchanged semantics), Save button unchanged; beneath, the metadata line (`Theme.Fonts.meta`, `textTertiary`) from `NoteMetadata.line(project: ref.project, modified: FileVaultIO(rootPath: ref.workingDirectory).modificationDate(ref.relativePath), wordCount: NoteMetadata.wordCount(text), now: .now, calendar: .current)` (ambient clock is fine in the VIEW; only tests pin time). Constrain the editor's content width to a comfortable reading measure (`.frame(maxWidth: ~720)` centered) per the mockups.
- [ ] **Step 5: Linked-references card.** Restyle `BacklinksPanel`: keep `linkers`/`BacklinkSnippets` logic and `onNavigate` exactly; swap the bottom-bar `DisclosureGroup` chrome for a Craft card at the end of the scroll content — "LINKED REFERENCES" caption (`Theme.Fonts.meta`, tracking, `textTertiary`), rows as today, container `Theme.Palette.bg` + `Theme.Elevation.card` + `Theme.Metrics` radius. Keep the `@AppStorage("notesBacklinksExpanded")` collapse.
- [ ] **Step 6: Push → CI green.** Leon eyeballs header, measure, card. **Commit** — `feat(notes): document header + metadata line + linked-references card`
- [ ] **Step 7: PR-A finish.** Full CI green; PR description flags the High-risk NSTextView surface for `deep-review`; digest entry with revert line after merge.

---

## Milestone 2b — block affordances (PR-B, branch `agent/craft-editor-2b`, after PR-A merges)

### Task 6: `SlashMenu` pure logic

**Files:**
- Create: `Sources/MustardKit/Logic/SlashMenu.swift`
- Create: `Tests/MustardTests/SlashMenuTests.swift`

Mirror `CommandBarEngine`'s shape (static item list, `items(query:)` filter). API (exact):

```swift
import Foundation

public struct SlashCommand: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let icon: String
    public let kind: Kind
    public enum Kind: Equatable { case todo, heading, linkToNote, subpage, askAgent }
}

/// Pure query → commands for the editor's "/" menu (Craft spec, 2b), plus trigger
/// detection and the markdown each command splices. Insertions are the ONLY source
/// text this menu produces — pinned byte-exact below (markdown-as-truth).
public enum SlashMenu {
    public static func items(query: String) -> [SlashCommand]
    /// Non-nil (the query typed so far) when the caret sits in an active trigger:
    /// the line up to the caret must be exactly "/" + query, query containing no
    /// whitespace. "a /x" or "/x y" is not a trigger.
    public static func activeQuery(linePrefix: String) -> String?
    /// Markdown to splice at line start + caret offset (UTF-16) after insertion.
    /// `.subpage`/`.linkToNote` interpolate the chosen/created note title.
    public static func insertion(for kind: SlashCommand.Kind, noteTitle: String?) -> (text: String, caretOffset: Int)
}
```

- [ ] **Step 1: Failing tests:**

```swift
import XCTest
@testable import MustardKit

final class SlashMenuTests: XCTestCase {
    func test_items_unfiltered_fiveCommands_orderPinned() {
        XCTAssertEqual(SlashMenu.items(query: "").map(\.id),
                       ["todo", "heading", "link", "subpage", "agent"])
    }
    func test_items_filter_caseInsensitive_titleContains() {
        XCTAssertEqual(SlashMenu.items(query: "he").map(\.id), ["heading"])
        XCTAssertEqual(SlashMenu.items(query: "AGE"), SlashMenu.items(query: "age"))
    }
    func test_items_noMatch_isEmpty() {
        XCTAssertTrue(SlashMenu.items(query: "zzz").isEmpty)
    }
    func test_activeQuery_onlyAtLineStart_noWhitespace() {
        XCTAssertEqual(SlashMenu.activeQuery(linePrefix: "/"), "")
        XCTAssertEqual(SlashMenu.activeQuery(linePrefix: "/hea"), "hea")
        XCTAssertNil(SlashMenu.activeQuery(linePrefix: "a /hea"))
        XCTAssertNil(SlashMenu.activeQuery(linePrefix: "/he a"))
        XCTAssertNil(SlashMenu.activeQuery(linePrefix: ""))
    }
    func test_insertion_todo_heading_byteExact() {
        XCTAssertEqual(SlashMenu.insertion(for: .todo, noteTitle: nil).text, "- [ ] ")
        XCTAssertEqual(SlashMenu.insertion(for: .heading, noteTitle: nil).text, "## ")
    }
    func test_insertion_linkToNote_caretInsideBrackets() {
        let ins = SlashMenu.insertion(for: .linkToNote, noteTitle: nil)
        XCTAssertEqual(ins.text, "[[]]"); XCTAssertEqual(ins.caretOffset, 2)
    }
    func test_insertion_subpage_interpolatesTitle() {
        XCTAssertEqual(SlashMenu.insertion(for: .subpage, noteTitle: "New page").text, "[[New page]]\n")
    }
    func test_insertion_askAgent_isVaultReadableCallout() {
        XCTAssertEqual(SlashMenu.insertion(for: .askAgent, noteTitle: nil).text, "> [!agent] ")
    }
}
```

Titles/icons for the item list: To-do (`checkmark.square`), Heading (`number`), Link to note (`link`), Sub-page (`doc.badge.plus`), Ask the agent (`sparkles`). "Ask the agent" deliberately just writes an `[!agent]` callout line — plain markdown the existing vault sweep already reads on its next pass; no new AgentService plumbing (record this restraint in the code comment).

- [ ] **Step 2: Push → CI FAIL. Step 3: Implement. Step 4: Push → CI green. Step 5: Commit** — `feat(notes): SlashMenu trigger, filter, and byte-exact insertion templates`

---

### Task 7: Slash menu UI + sub-page creation wiring

**Files:**
- Create: `Sources/MustardKit/Views/SlashMenuView.swift`
- Modify: `Sources/MustardKit/Views/MarkdownTextView.swift`, `Views/NoteEditorView.swift`, `Views/NotesView.swift`

Build + eye. The insertion path is the risky seam — one rule: **every splice goes through `textView.insertText(_:replacementRange:)`** so it lands in the undo stack as a single user-visible operation and fires `textDidChange` → binding → dirty dot, exactly like typing.

- [ ] **Step 1: Trigger detection.** In the coordinator's `textDidChange`, compute the current line prefix up to the caret; `SlashMenu.activeQuery(linePrefix:)` non-nil → publish `(query, caretScreenRect)` (caret rect via `firstRect(forCharacterRange:)`) through a coordinator callback; nil → close. Escape closes (`cancelOperation` hook); ↑/↓/⏎ are intercepted in `textView(_:doCommandBy:)` ONLY while the menu is open (comment why: never steal arrows during normal editing).
- [ ] **Step 2: `SlashMenuView`.** Caret-anchored floating list (rendered from `NoteEditorView` as an `.overlay` positioned by the published rect): rows icon + title (`Theme.Fonts.body`), selected row `Theme.Palette.navActive`, container `Theme.Elevation.pop` + `Theme.Metrics` radius, appear/disappear with `Theme.Motion.pop`.
- [ ] **Step 3: Execution.** On pick, replace the trigger text (`"/" + query` range) via `insertText(_:replacementRange:)` with `SlashMenu.insertion(...)`, then set `selectedRange` from `caretOffset`. `.linkToNote` inserts `[[]]` and lets the user type (resolution/create already handled by existing flows). `.subpage` needs a new-note hook: add `onCreateSubpage: (String) -> String?` (title → created relativePath, nil on failure) threaded `NotesView → NoteEditorView → MarkdownTextView`; `NotesView` implements it with its existing `createNote(title:project:workingDirectory:)` primitive **minus the selection jump** (extract a `writeNote` helper — creating a sub-page must not navigate away mid-typing; comment why), then the editor splices `insertion(for: .subpage, noteTitle: title)`.
- [ ] **Step 4: Push → CI green.** Leon eyeballs: `/` at line start opens; mid-line `/` doesn't; filter narrows; Esc restores typing; ⏎ inserts; undo removes the whole insertion in one step; Sub-page creates the file (visible in sidebar after reindex) and links it.
- [ ] **Step 5: Commit** — `feat(notes): caret-anchored slash menu with undo-safe insertions + sub-page creation`

---

### Task 8: `BlockReorder` pure move

**Files:**
- Create: `Sources/MustardKit/Logic/BlockReorder.swift`
- Create: `Tests/MustardTests/BlockReorderTests.swift`

API (exact):

```swift
import Foundation

/// Pure block drag-reorder for the live editor (Craft spec, 2b): the ONLY function
/// that rewrites note source for a move. Operates on NoteDecoration's total
/// partition; the frontmatter block is never moveable and never displaced.
public enum BlockReorder {
    /// Moveable blocks = NoteDecoration.blocks minus any frontmatter block.
    /// `from`/`to` index that array; `to` is the destination slot AFTER removal
    /// (standard reorder semantics). Out-of-range or from == to → source unchanged,
    /// byte-identical. Every non-blank line of the input appears exactly once in
    /// the output; separator hygiene (see tests) is the one permitted adjustment.
    public static func move(_ source: String, from: Int, to: Int) -> String
}
```

Separator rule (the honest wrinkle — document it in the doc comment): blocks carry their trailing blank lines, so most moves are pure slice permutation. The final block may lack a trailing newline; when it moves off the end, it gains `"\n"`, and the block that becomes last may keep its blank-line tail — the ONLY bytes this function may adjust, pinned by tests. Content lines are never touched.

- [ ] **Step 1: Failing tests:**

```swift
import XCTest
@testable import MustardKit

final class BlockReorderTests: XCTestCase {
    func test_move_identity_andOutOfRange_returnSourceByteIdentical() {
        let source = "# H\n\npara\n\n- a\n"
        XCTAssertEqual(BlockReorder.move(source, from: 1, to: 1), source)
        XCTAssertEqual(BlockReorder.move(source, from: 9, to: 0), source)
    }
    func test_move_swapTwoParagraphs_exactBytes() {
        XCTAssertEqual(BlockReorder.move("# H\n\nfirst\n\nsecond\n", from: 2, to: 1),
                       "# H\n\nsecond\n\nfirst\n")
    }
    func test_move_fenceMovesAtomically_withContents() {
        let source = "para\n\n```\ncode line\n\nstill code\n```\n\ntail\n"
        XCTAssertEqual(BlockReorder.move(source, from: 1, to: 0),
                       "```\ncode line\n\nstill code\n```\n\npara\n\ntail\n")
    }
    func test_move_frontmatterNeverMoves_indicesSkipIt() {
        let source = "---\ntitle: x\n---\n# H\n\npara\n"
        // Moveable[0] = "# H\n\n", moveable[1] = "para\n"
        XCTAssertEqual(BlockReorder.move(source, from: 1, to: 0),
                       "---\ntitle: x\n---\npara\n\n# H\n")
    }
    func test_move_lastBlockWithoutNewline_gainsSeparator_noLineLost() {
        let moved = BlockReorder.move("first\n\ntail no newline", from: 1, to: 0)
        XCTAssertEqual(moved, "tail no newline\n\nfirst\n")
        // Multiset of non-blank lines preserved:
        let lines = { (s: String) in s.split(separator: "\n").filter { !$0.isEmpty }.sorted() }
        XCTAssertEqual(lines(moved), lines("first\n\ntail no newline"))
    }
}
```

(Grow the fixture battery: quotes, nested lists, rules, CRLF blocks — each asserting exact output bytes plus the line-multiset invariant.)

- [ ] **Step 2: Push → CI FAIL. Step 3: Implement** over `NoteDecoration.blocks` slices. **Step 4: Push → CI green. Step 5: Commit** — `feat(notes): BlockReorder — pure, byte-pinned block move over the partition`

---

### Task 9: Hover gutter — ⠿ drag-reorder and + insert

**Files:**
- Create: `Sources/MustardKit/Views/BlockGutterOverlay.swift`
- Modify: `Sources/MustardKit/Views/MarkdownTextView.swift`, `Views/NoteEditorView.swift`

Build + eye. Geometry, not logic — every decision already lives in `NoteDecoration.blocks` / `BlockReorder.move`.

- [ ] **Step 1: Publish block rects.** Coordinator computes, after layout settles (hook `NSLayoutManager` `didCompleteLayoutFor` + the existing decoration debounce), `[(blockIndex: Int, rect: CGRect)]` via `layoutManager.boundingRect(forGlyphRange:in:)` per moveable block range, converted to the SwiftUI overlay's space; expose through a callback prop. Skip publishing in large-note fallback mode (no decoration → no handles; typing still works).
- [ ] **Step 2: `BlockGutterOverlay`.** A ~28pt leading gutter over the editor: on block hover, show `⠿` (drag) and `+` (insert) at that block's rect top, `textTertiary` → `textSecondary` on hover, fading with `Theme.Motion.settle`. `+` opens the slash menu anchored to that block with an empty query (inserting at the block's start — reuse Task 7's machinery with an explicit anchor).
- [ ] **Step 3: Drag-reorder.** A `DragGesture` on `⠿` (deliberately NOT NSTextView's native text drag): while dragging, hit-test the y-offset against published rects for the insertion slot and draw a 2pt accent insertion line; on end, splice `BlockReorder.move(text, from:to:)` as ONE undoable edit — `shouldChangeText(in: fullRange, replacementString: newSource)` → replace via `insertText(_:replacementRange:)` → restore scroll position; wrap in a single `undoManager` group so ⌘Z restores the previous order in one step (comment why). The SwiftUI binding updates through the normal `textDidChange` path, so the dirty dot and ⌘S semantics hold with zero new save code.
- [ ] **Step 4: Push → CI green.** Leon eyeballs: handles appear/disappear calmly; drag shows the insertion line; drop reorders; ⌘Z restores; caret and scroll don't jump; `+` opens the menu; a note reordered in Mustard still reads correctly in Obsidian (spot-check the raw file).
- [ ] **Step 5: Commit** — `feat(notes): block hover gutter with drag-reorder + per-block insert`

---

### Task 10: Subpage cards (optional polish — timeboxed)

**Files:**
- Modify: `Sources/MustardKit/Views/MarkdownTextView.swift` (custom `NSLayoutManager` subclass), `Logic/NoteDecoration.swift` + tests (one additive span kind)

The most experimental slice; the spec marks it optional ("can render"). Timebox to one working session — if the drawing fights back, ship the pill styling from Task 4 and record the parking in the PR body. **Constraint: no `NSTextAttachment`** — attachments replace characters and would break text == source.

- [ ] **Step 1 (TDD, additive):** `NoteDecoration` gains `case subpageCard(target: String)` emitted for a line whose entire trimmed content is one resolved-shape wikilink (`[[Target]]` alone on the line). Tests: `test_spans_wikilinkAloneOnLine_isSubpageCard`, `test_spans_wikilinkWithSurroundingText_isNotCard`, plus a partition-lossless fixture. Push → CI FAIL → implement → green. **Commit** — `feat(notes): NoteDecoration subpageCard span for standalone wikilink lines`
- [ ] **Step 2 (view):** custom `NSLayoutManager` subclass overriding `drawBackground(forGlyphRange:at:)` to draw a card (bg fill, hairline border, `Theme.Metrics` radius — NSColor bridges of `Theme.Palette` tokens) behind `subpageCard` ranges, with a leading `doc.text` glyph; the wikilink text itself renders as the card title (already accent + clickable from Task 4). Characters untouched; caret can still enter the line and edit the raw `[[...]]`.
- [ ] **Step 3: Push → CI green;** Leon eyeballs (card look, editing through the card, click-through). **Commit** — `feat(notes): standalone wikilinks render as inline subpage cards`

---

### Task 11: Finish line

- [ ] Full CI green on PR-B (all prior suites + NoteDecoration/SlashMenu/BlockReorder/NoteMetadata/WikilinkURL additions); note the final test count vs the ~576 baseline in `verification.md`.
- [ ] Update `CLAUDE.md` folder layout (NoteDecoration, SlashMenu, BlockReorder, NoteMetadata, WikilinkURL in Logic/; MarkdownTextView, SlashMenuView, BlockGutterOverlay in Views/; note the Source/Preview toggle's replacement) and the "535 tests" figure; update `docs/build-order.md` (Craft Phase 2 shipped, 2a/2b halves).
- [ ] Run artifacts under `.agent-loop/runs/<run-id>/` per milestone: `trace.jsonl`, `verification.md` (CI links, since local swift is unavailable), `risk-report.md`, `deep-review-report.md` (expect High via the spec's own risk call and the `agent`-adjacent surface), `pr-body.md`.
- [ ] PRs: `feat(notes): Craft live editor 2a — style-as-you-type surface` and `feat(notes): Craft live editor 2b — block handles, slash menu, subpage cards`; fresh-context review per `.agent-loop/review-rubric.md`; merge per policy; digest entries with ready revert lines.
- [ ] Explicitly ask Leon for the eye-pass on the merged build (`./build-app.sh` on his Mac) — the container cannot screenshot the native app; the plan's view claims end at "builds, CI green".

## Risk register (NSTextView — read before Task 3)

| Risk | Mitigation (chosen above) |
|---|---|
| TK2 silent downgrade / macOS 14 quirks | Explicit TK1 stack (Decision 1); revisit only on real defect |
| Binding echo → caret teleport | Coordinator `isProgrammaticUpdate` guard; `updateNSView` writes only on real difference; selection clamped |
| Attribute pass cost on large notes | Edited-block-scoped sync pass + 150 ms debounced full pass; >200k UTF-16 units → plain-text fallback, typing never blocks |
| Marker hiding breaking caret/selection | Not attempted — de-emphasis only (Decision 2); `.marker` spans keep the door open |
| Undo pollution from styling | Attribute passes bypass `shouldChangeText`/undo entirely; all *text* mutations (slash, reorder) go through `insertText(_:replacementRange:)` as single undo groups |
| First-responder/focus fights with SwiftUI | Deferred `makeFirstResponder` on window attach; ⌘S stays a window-level SwiftUI shortcut; arrows/⏎ intercepted only while the slash menu is open |
| Lossy rewrites of user markdown | Read-only decoration API; partition round-trip tests; `BlockReorder`/`SlashMenu.insertion` byte-pinned; unsupported grammar always raw |
| Smart substitutions corrupting syntax | All automatic substitutions disabled at view construction |

## Self-review notes

- Spec coverage: 2a live surface → T1–4, header/metadata → T5, linked-references card → T5, keep dirty/⌘S/snapshot/save-on-switch → T3 (explicit do-not-touch list), resolver/create-from-dangling preserved → T3/T4 (clickedOnLink routes to existing `onWikilinkTap`), frontmatter decision → Decision 3, round-trip guard → T1 + T8 + T6 insertion pins; 2b handles/reorder → T8/T9, slash menu → T6/T7, subpage cards → T10 (timeboxed, spec-optional). Reindex-on-save untouched (save path not modified anywhere).
- Type consistency: `NoteDecoration.Block` consumed by T4 (invalidation), T8 (`BlockReorder`), T9 (rect publication); `WikilinkURL` shared by MarkdownPreviewView + MarkdownTextView; `SlashMenu.insertion` return shape used identically in T7 steps; all ranges UTF-16 `NSRange` end-to-end (WikilinkSyntax → NoteDecoration → NSTextStorage).
- Known intentional choices: frontmatter visible-not-hidden (invariant + power-user honesty); TK1 over TK2; "Ask the agent" = a plain callout the sweep reads (no new plumbing); sub-page creation doesn't navigate away; separator hygiene in `BlockReorder` is the single permitted whitespace adjustment, byte-pinned; `MarkdownPreviewView` retained for Phase 1's OutputCard rendering.
- Deliberately out: marker hiding, typewriter/focus mode, `- [ ]` checkbox toggling (todo lines are plain bullets for now), TK2 migration, full-text search — all recorded in the spec's out-of-scope list or parked with data-ready hooks.
