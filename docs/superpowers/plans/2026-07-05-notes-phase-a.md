# Notes Phase A — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vault-file-native markdown notes inside Mustard — a Notes tab that browses every `.md` file across all configured projects, edits them with a Source/Preview toggle, resolves `[[wikilinks]]`, and shows backlinks — backed by a `NoteIndexEntry` SwiftData mirror rebuilt by a cheap filesystem reindex.

**Architecture:** Real `.md` files stay the source of truth (read/written via `FileVaultIO`, generalized behind a new `NoteVaultIO` protocol). Pure logic (`WikilinkIndex`, `MarkdownBlocks`, `NoteTree`, `NoteCreation`, `NoteReindexScheduler`) is TDD'd in `Logic/`. A `NoteIndexService` orchestrator rebuilds per-project `NoteIndexEntry` rows on a 300s throttle inside the existing 60s app loop, on save, and on a manual ⌘K command. Views only render and dispatch.

**Tech Stack:** Swift 5.9 SPM, SwiftUI (macOS 14), SwiftData, XCTest. No new dependencies.

**Backing docs:** `docs/specs/2026-07-05-notes-vault-backlinks-design.md` (incl. the Technical review addendum — read both before starting any task). Linear epic BAK-145.

**Conventions that bind every task (from CLAUDE.md):**
- TDD for anything in `Logic/` or pure `Agent/` functions: failing test first, then implement. One test file per unit.
- Pin time/zone in tests: fixed dates via `ISO8601DateFormatter`/`Date(timeIntervalSince1970:)`, inject `now:`. Never the ambient clock.
- Views: no unit tests — `swift build` must pass; never claim a view "looks right", only that it builds.
- Colors/fonts only from `Theme.Palette` / `Theme.Fonts` (`Sources/MustardKit/Logic/Theme.swift`).
- Commits: `type(scope): summary` + `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`. Bite-sized, test-passing.
- Run tests: `swift test --filter <SuiteName>` per task, full `swift test` + `swift build` before finishing a task.

**File map (whole feature):**

| File | Task | Responsibility |
|---|---|---|
| `Sources/MustardKit/Agent/FileVaultIO.swift` (modify) | 1 | `NoteVaultIO` protocol + whole-vault `notePaths()` / `modificationDate(_:)` |
| `Tests/MustardTests/FileVaultIOTests.swift` (create) | 1 | temp-dir scanner tests |
| `Sources/MustardKit/Logic/WikilinkIndex.swift` (create) | 2 | frontmatter + wikilink parsing, resolution, backlink graph |
| `Tests/MustardTests/WikilinkIndexTests.swift` (create) | 2 | |
| `Sources/MustardKit/Logic/MarkdownBlocks.swift` (create) | 3 | markdown → render blocks + inline wikilink runs |
| `Tests/MustardTests/MarkdownBlocksTests.swift` (create) | 3 | |
| `Sources/MustardKit/Models/NoteIndexEntry.swift` (create) | 4 | @Model mirror row |
| `Sources/MustardKit/Logic/NoteReindexScheduler.swift` (create) | 4 | pure 300s throttle |
| `Sources/MustardKit/Agent/NoteIndexService.swift` (create) | 4 | reindex orchestrator (@Observable) |
| `Tests/MustardTests/NoteReindexSchedulerTests.swift`, `Tests/MustardTests/NoteIndexServiceTests.swift` (create) | 4 | |
| `Sources/MustardKit/MustardContainer.swift`, `PreviewData.swift`, `Sources/Mustard/MustardApp.swift`, `Logic/CommandBarEngine.swift`, `Views/CommandBarView.swift` (modify) | 4 | registration + loop + ⌘K wiring |
| `Sources/MustardKit/Logic/NoteTree.swift` (create) + tests | 5 | paths → folder tree + filter |
| `Sources/MustardKit/Views/NotesView.swift` (create), `Views/RootView.swift` (modify) | 5 | Notes tab, project sidebar, tree, filter box |
| `Sources/MustardKit/Views/NoteEditorView.swift`, `Views/MarkdownPreviewView.swift` (create) | 6 | source editor, preview, save flow |
| `Sources/MustardKit/Logic/BacklinkSnippets.swift` (create) + tests, `Views/BacklinksPanel.swift` (create) | 7 | backlinks panel |
| `Sources/MustardKit/Logic/NoteCreation.swift` (create) + tests, NotesView "+" | 8 | new-note stub + filename collision |
| wikilink tap wiring in NotesView/preview | 9 | navigate / create-from-unresolved |

Dependencies: 1, 2, 3 are independent. 4 needs 1+2. 5 needs 4. 6 needs 3+4+5. 7 needs 6. 8 needs 5. 9 needs 6+8.

---

### Task 1: Generalized vault scanner — `NoteVaultIO` (BAK-146)

**Files:**
- Modify: `Sources/MustardKit/Agent/FileVaultIO.swift`
- Create: `Tests/MustardTests/FileVaultIOTests.swift`

`FileVaultIO.meetingNotePaths()` and the `MeetingVaultIO` protocol (in `Agent/MeetingTaskSync.swift`) must NOT change — meeting sync depends on them.

- [ ] **Step 1: Write the failing tests** — temp-dir pattern copied from `Tests/MustardTests/FileBridgeIOTests.swift`:

```swift
import XCTest
@testable import MustardKit

final class FileVaultIOTests: XCTestCase {
    private var dir: String!
    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "vault-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: dir) }

    private func put(_ rel: String, _ contents: String = "# x\n") throws {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func test_notePaths_enumeratesAllMarkdown_sorted() throws {
        try put("readme.md"); try put("guides/setup.md"); try put("meetings/2026/sync.md")
        try put("guides/img.png")                                   // non-md excluded
        let io = FileVaultIO(rootPath: dir)
        XCTAssertEqual(io.notePaths(), ["guides/setup.md", "meetings/2026/sync.md", "readme.md"])
    }

    func test_notePaths_prunesStructuralAndAgentFolders() throws {
        try put("keep.md")
        for skip in ["node_modules/a.md", ".build/b.md", "_artifacts/c.md",
                     "_recs/d.md", "_agent/e.md", "hub/notes/f.md", "sub/node_modules/g.md"] {
            try put(skip)
        }
        XCTAssertEqual(FileVaultIO(rootPath: dir).notePaths(), ["keep.md"])
    }

    func test_notePaths_keepsFiledFolder() throws {
        // ADR-0009 hides _filed/ from the sweep; the Notes browser keeps it visible.
        try put("_filed/inbox-log.md")
        XCTAssertEqual(FileVaultIO(rootPath: dir).notePaths(), ["_filed/inbox-log.md"])
    }

    func test_modificationDate_returnsDateForExisting_nilForMissing() throws {
        try put("a.md")
        let io = FileVaultIO(rootPath: dir)
        XCTAssertNotNil(io.modificationDate("a.md"))
        XCTAssertNil(io.modificationDate("nope.md"))
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter FileVaultIOTests` → FAIL (`notePaths` undefined).

- [ ] **Step 3: Implement** in `FileVaultIO.swift` — add the protocol above the struct, conform, and add the two methods. The enumerator body mirrors `meetingNotePaths()` (reuse its `relativePath(of:)` helper):

```swift
/// Whole-vault note access for the Notes surface (BAK-146). Same IO boundary as
/// `MeetingVaultIO`, but enumerates every `.md` file rather than `meetings/` only.
public protocol NoteVaultIO {
    func notePaths() -> [String]
    func read(_ relativePath: String) -> String?
    func write(_ relativePath: String, _ contents: String) throws
    func snapshot(_ relativePath: String, _ contents: String) throws
    func modificationDate(_ relativePath: String) -> Date?
}

extension FileVaultIO: NoteVaultIO {
    /// Structural prune (as meetingNotePaths) + Mustard/agent scratch. `_filed/`
    /// stays visible — Notes is a human-browsing surface (spec: Ignore rules).
    public func notePaths() -> [String] {
        let prune: Set<String> = ["node_modules", ".git", ".build", "_artifacts",
                                  ".obsidian", "_recs", "_agent", "hub", ".snapshots"]
        guard let walker = fileManager.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        var paths: [String] = []
        for case let url as URL in walker {
            if prune.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
            guard url.pathExtension == "md" else { continue }
            paths.append(relativePath(of: url))
        }
        return paths.sorted()
    }

    public func modificationDate(_ relativePath: String) -> Date? {
        let path = root.appendingPathComponent(relativePath).path
        return (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
```

Note `root` and `fileManager` are `private let` — change both to `let` (no access-level keyword works since the extension is same-file; `private` is fine for same-file extensions in Swift, so actually no change needed — verify it compiles as-is first).

- [ ] **Step 4: Run** — `swift test --filter FileVaultIOTests` → PASS. Then full `swift test` (all 73+ green) and `swift build`.

- [ ] **Step 5: Commit** — `feat(notes): generalize vault scanner behind NoteVaultIO (BAK-146)`

---

### Task 2: `WikilinkIndex` (BAK-147)

**Files:**
- Create: `Sources/MustardKit/Logic/WikilinkIndex.swift`
- Create: `Tests/MustardTests/WikilinkIndexTests.swift`

Pure, no Foundation-FS, no clock. API:

```swift
/// One parsed note: frontmatter stripped, links extracted (not yet resolved).
public struct ParsedNote: Equatable {
    public let relativePath: String
    public let title: String          // frontmatter title ?? first "# " heading ?? filename sans .md
    public let tags: [String]
    public let body: String           // content minus frontmatter block
    public let links: [WikilinkOccurrence]
}

public struct WikilinkOccurrence: Equatable {
    public let target: String         // "Note" from [[Note]], [[Note#H]], [[Note|alias]], ![[Note]]
    public let alias: String?
    public let line: String           // full containing line (backlink snippet context)
}

public struct Backlink: Equatable {
    public let sourcePath: String     // note containing the link
    public let snippet: String        // the containing line
}

public struct WikilinkIndex: Equatable {
    public let notes: [ParsedNote]                    // sorted by relativePath
    public let forwardLinks: [String: [String]]       // path → resolved target paths (deduped, link order)
    public let backlinks: [String: [Backlink]]        // path → links into it (sorted by sourcePath)

    public static func build(_ docs: [(relativePath: String, content: String)]) -> WikilinkIndex
    /// Deterministic resolution (addendum #6): exact-path first for "/" targets,
    /// else case-insensitive filename match over candidates sorted by
    /// (path-component count, then lexicographic). nil if nothing matches.
    public static func resolve(target: String, in paths: [String]) -> String?
}

/// Minimal YAML frontmatter reader — only what Phase A needs (title, tags).
public enum Frontmatter {
    /// Detects a leading "---\n...\n---" block. Returns nil title/empty tags when absent.
    public static func parse(_ content: String) -> (title: String?, tags: [String], body: String)
}
```

- [ ] **Step 1: Write the failing tests:**

```swift
import XCTest
@testable import MustardKit

final class WikilinkIndexTests: XCTestCase {
    // MARK: Frontmatter
    func test_frontmatter_titleAndInlineTags() {
        let (title, tags, body) = Frontmatter.parse("---\ntitle: My Note\ntags: [a, b]\n---\nBody")
        XCTAssertEqual(title, "My Note"); XCTAssertEqual(tags, ["a", "b"]); XCTAssertEqual(body, "Body")
    }
    func test_frontmatter_blockListTags() {
        let (_, tags, _) = Frontmatter.parse("---\ntags:\n  - alpha\n  - beta\n---\nx")
        XCTAssertEqual(tags, ["alpha", "beta"])
    }
    func test_frontmatter_absent_returnsWholeBody() {
        let (title, tags, body) = Frontmatter.parse("# Hi\nText")
        XCTAssertNil(title); XCTAssertEqual(tags, []); XCTAssertEqual(body, "# Hi\nText")
    }
    func test_frontmatter_unterminated_isNotFrontmatter() {
        let (title, _, body) = Frontmatter.parse("---\ntitle: x\nno end")
        XCTAssertNil(title); XCTAssertEqual(body, "---\ntitle: x\nno end")
    }

    // MARK: Title derivation
    func test_title_prefersFrontmatter_thenHeading_thenFilename() {
        let idx = WikilinkIndex.build([
            ("a.md", "---\ntitle: Custom\n---\n# Heading"),
            ("b.md", "# From Heading\ntext"),
            ("dir/c.md", "plain text"),
        ])
        XCTAssertEqual(idx.notes.map(\.title), ["Custom", "From Heading", "c"])
    }

    // MARK: Extraction
    func test_links_plainAliasHeadingAndEmbed() {
        let idx = WikilinkIndex.build([
            ("a.md", "See [[Target]] and [[Target#Section]] and [[Target|the alias]] and ![[Target]]"),
            ("Target.md", "x"),
        ])
        let links = idx.notes[0].links
        XCTAssertEqual(links.map(\.target), ["Target", "Target", "Target", "Target"])
        XCTAssertEqual(links[2].alias, "the alias")
        XCTAssertEqual(idx.forwardLinks["a.md"], ["Target.md"])   // deduped
    }
    func test_links_insideCodeFences_ignored() {
        let idx = WikilinkIndex.build([
            ("a.md", "```\n[[NotALink]]\n```\n[[Real]]"), ("Real.md", "x"), ("NotALink.md", "x"),
        ])
        XCTAssertEqual(idx.forwardLinks["a.md"], ["Real.md"])
    }

    // MARK: Resolution
    func test_resolve_caseInsensitive_extensionStripped() {
        XCTAssertEqual(WikilinkIndex.resolve(target: "setup", in: ["guides/Setup.md"]), "guides/Setup.md")
        XCTAssertEqual(WikilinkIndex.resolve(target: "Setup.md", in: ["guides/Setup.md"]), "guides/Setup.md")
    }
    func test_resolve_duplicateTitles_shallowestThenLexicographic() {
        let paths = ["z/deep/Setup.md", "b/Setup.md", "a/Setup.md"]
        XCTAssertEqual(WikilinkIndex.resolve(target: "Setup", in: paths), "a/Setup.md")
    }
    func test_resolve_pathQualified_exactMatchFirst() {
        let paths = ["guides/Setup.md", "Setup.md"]
        XCTAssertEqual(WikilinkIndex.resolve(target: "guides/Setup", in: paths), "guides/Setup.md")
    }
    func test_resolve_unresolved_returnsNil() {
        XCTAssertNil(WikilinkIndex.resolve(target: "Ghost", in: ["a.md"]))
    }

    // MARK: Backlinks
    func test_backlinks_carryContainingLineSnippet_sortedBySource() {
        let idx = WikilinkIndex.build([
            ("b.md", "line before\nsee [[Home]] for details\nafter"),
            ("a.md", "top [[Home]]"),
            ("Home.md", "# Home"),
        ])
        XCTAssertEqual(idx.backlinks["Home.md"], [
            Backlink(sourcePath: "a.md", snippet: "top [[Home]]"),
            Backlink(sourcePath: "b.md", snippet: "see [[Home]] for details"),
        ])
        XCTAssertNil(idx.backlinks["a.md"])   // or empty — pick one, assert it
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter WikilinkIndexTests` → FAIL (types undefined).

- [ ] **Step 3: Implement `Logic/WikilinkIndex.swift`.** Implementation notes (write real code, this is the shape):
  - `Frontmatter.parse`: split into lines; require line 0 == `---`; find next `---` line; between them, match `title: value` (trim, strip surrounding quotes) and `tags:` — inline `[a, b]` split on comma, or subsequent `  - item` lines. No general YAML — keys other than title/tags ignored. Unterminated → treat whole content as body.
  - Link extraction: iterate body lines, toggle in-fence on lines starting with ```` ``` ````; regex on non-fence lines: `/!?\[\[([^\]\|#]+)(?:#[^\]\|]*)?(?:\|([^\]]+))?\]\]/` (use `NSRegularExpression` or Swift `Regex`; trim target/alias whitespace).
  - `build`: parse all docs → notes sorted by path; resolution candidates = all relativePaths; forwardLinks resolves each occurrence via `resolve`, drops nils and self-links? (keep self-links — harmless), dedupes preserving order; backlinks inverted from forwardLinks *per occurrence* (source path + its `line`), sorted by sourcePath; only keys with non-empty arrays present.
  - `resolve`: if target contains `/`: exact case-insensitive match on path-with-`.md`-appended (if not already) first. Else filename comparison: `lastPathComponent` minus `.md`, case-insensitive, over candidates sorted by (components.count, path).

- [ ] **Step 4: Run** — `swift test --filter WikilinkIndexTests` → PASS; full `swift test` + `swift build`.

- [ ] **Step 5: Commit** — `feat(notes): WikilinkIndex — frontmatter, wikilinks, backlink graph (BAK-147)`

---

### Task 3: `MarkdownBlocks` preview parser (logic half of BAK-150)

**Files:**
- Create: `Sources/MustardKit/Logic/MarkdownBlocks.swift`
- Create: `Tests/MustardTests/MarkdownBlocksTests.swift`

Pure markdown → block list for the preview renderer (addendum #4). Inline bold/italic is NOT parsed here — the view renders non-wikilink text runs through `AttributedString(markdown:)`; this parser only isolates block structure and wikilink tap targets.

```swift
public enum InlineRun: Equatable {
    case text(String)                                  // may contain **md** — view renders via AttributedString
    case wikilink(target: String, alias: String?)      // display alias ?? target
}

public enum MarkdownBlock: Equatable {
    case heading(level: Int, runs: [InlineRun])        // level 1...6
    case bullet(runs: [InlineRun], indent: Int)        // indent = leading spaces / 2
    case ordered(runs: [InlineRun], indent: Int)
    case quote(runs: [InlineRun])
    case code(String)                                  // fence contents verbatim, no runs
    case rule                                          // --- / *** line
    case paragraph(runs: [InlineRun])                  // consecutive non-blank lines joined by \n
}

public enum MarkdownBlocks {
    /// `body` is frontmatter-stripped content (callers use Frontmatter.parse first).
    public static func parse(_ body: String) -> [MarkdownBlock]
    /// Split one line of text into text/wikilink runs (shared with heading/bullet/quote parsing).
    public static func runs(_ line: String) -> [InlineRun]
}
```

- [ ] **Step 1: Write the failing tests:**

```swift
import XCTest
@testable import MustardKit

final class MarkdownBlocksTests: XCTestCase {
    func test_headings_levels() {
        XCTAssertEqual(MarkdownBlocks.parse("# One\n### Three"), [
            .heading(level: 1, runs: [.text("One")]),
            .heading(level: 3, runs: [.text("Three")]),
        ])
    }
    func test_paragraph_joinsConsecutiveLines_blankSeparates() {
        XCTAssertEqual(MarkdownBlocks.parse("a\nb\n\nc"), [
            .paragraph(runs: [.text("a\nb")]), .paragraph(runs: [.text("c")]),
        ])
    }
    func test_bullets_withIndent_andOrdered() {
        XCTAssertEqual(MarkdownBlocks.parse("- top\n  - nested\n1. first"), [
            .bullet(runs: [.text("top")], indent: 0),
            .bullet(runs: [.text("nested")], indent: 1),
            .ordered(runs: [.text("first")], indent: 0),
        ])
    }
    func test_codeFence_capturedVerbatim_noWikilinkRuns() {
        XCTAssertEqual(MarkdownBlocks.parse("```swift\nlet a = [[1]]\n```"), [.code("let a = [[1]]")])
    }
    func test_quote_and_rule() {
        XCTAssertEqual(MarkdownBlocks.parse("> hi\n---"), [.quote(runs: [.text("hi")]), .rule])
    }
    func test_runs_splitsWikilinks_keepsAlias() {
        XCTAssertEqual(MarkdownBlocks.runs("see [[A|alias]] and [[B]] end"), [
            .text("see "), .wikilink(target: "A", alias: "alias"),
            .text(" and "), .wikilink(target: "B", alias: nil), .text(" end"),
        ])
    }
    func test_wikilinkInsideHeadingAndBullet() {
        XCTAssertEqual(MarkdownBlocks.parse("# About [[Home]]\n- go [[Home]]"), [
            .heading(level: 1, runs: [.text("About "), .wikilink(target: "Home", alias: nil)]),
            .bullet(runs: [.text("go "), .wikilink(target: "Home", alias: nil)], indent: 0),
        ])
    }
}
```

- [ ] **Step 2: Run to verify failure.** `swift test --filter MarkdownBlocksTests` → FAIL.
- [ ] **Step 3: Implement.** Line-based state machine: fence toggle → code accumulation; `#{1,6} ` → heading; `- ` / `* ` (with leading-space indent) → bullet; `\d+\. ` → ordered; `> ` → quote; `---`/`***` alone → rule (only when not already in a paragraph? keep simple: a `---` line always → rule since frontmatter is pre-stripped); else paragraph accumulation. `runs(_:)` reuses the same wikilink regex as Task 2 (fine to duplicate the pattern string; keep target/alias trimming identical). Embeds `![[x]]` render as plain wikilinks.
- [ ] **Step 4: Run** — suite PASS, full `swift test` + `swift build`.
- [ ] **Step 5: Commit** — `feat(notes): MarkdownBlocks preview parser (BAK-150 logic)`

---

### Task 4: `NoteIndexEntry` model + reindex service + wiring (BAK-148)

**Files:**
- Create: `Sources/MustardKit/Models/NoteIndexEntry.swift`
- Create: `Sources/MustardKit/Logic/NoteReindexScheduler.swift`
- Create: `Sources/MustardKit/Agent/NoteIndexService.swift`
- Create: `Tests/MustardTests/NoteReindexSchedulerTests.swift`, `Tests/MustardTests/NoteIndexServiceTests.swift`
- Modify: `Sources/MustardKit/MustardContainer.swift` (add `NoteIndexEntry.self` to the `ModelContainer(for:)` list), `Sources/MustardKit/PreviewData.swift` (same + 2 sample entries), `Sources/Mustard/MustardApp.swift` (service + loop call), `Sources/MustardKit/Logic/CommandBarEngine.swift` + `Sources/MustardKit/Views/CommandBarView.swift` (⌘K commands)

- [ ] **Step 1: Model** (defaults on every property — CloudKit-compatible, ADR-0001, exactly like `Recommendation`):

```swift
import Foundation
import SwiftData

/// SwiftData mirror of one vault `.md` file (Notes Phase A, BAK-148). The file is
/// the source of truth; this row exists for fast search/backlinks and the future
/// mobile read-only view (N2). Keyed (project, relativePath) — project is the KB
/// folder name (matches SourceConfig.project), NOT SourceID (see spec addendum #1).
@Model
public final class NoteIndexEntry {
    public var project: String = ""
    public var relativePath: String = ""
    public var title: String = ""
    public var tags: [String] = []
    public var lastModified: Date = Date.distantPast
    public var forwardLinks: [String] = []
    public var contentSnapshot: String = ""

    public init(project: String = "", relativePath: String = "", title: String = "",
                tags: [String] = [], lastModified: Date = .distantPast,
                forwardLinks: [String] = [], contentSnapshot: String = "") {
        self.project = project; self.relativePath = relativePath; self.title = title
        self.tags = tags; self.lastModified = lastModified
        self.forwardLinks = forwardLinks; self.contentSnapshot = contentSnapshot
    }
}
```

- [ ] **Step 2: Failing scheduler tests:**

```swift
import XCTest
@testable import MustardKit

final class NoteReindexSchedulerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)
    func test_neverIndexed_isDue() {
        XCTAssertTrue(NoteReindexScheduler.isDue(lastIndexedAt: nil, now: t0))
    }
    func test_withinInterval_notDue_afterInterval_due() {
        XCTAssertFalse(NoteReindexScheduler.isDue(lastIndexedAt: t0, now: t0.addingTimeInterval(299)))
        XCTAssertTrue(NoteReindexScheduler.isDue(lastIndexedAt: t0, now: t0.addingTimeInterval(300)))
    }
}
```

- [ ] **Step 3: Implement scheduler** (mirror `SweepScheduler`'s shape):

```swift
import Foundation

/// Pure due-logic for the cheap notes reindex (spec addendum #2): minutes, not the
/// hours-scale claude-sweep cadence. Runs inside the existing 60s app loop.
public enum NoteReindexScheduler {
    public static let defaultInterval: TimeInterval = 300
    public static func isDue(lastIndexedAt: Date?, now: Date, interval: TimeInterval = defaultInterval) -> Bool {
        guard let last = lastIndexedAt else { return true }
        return now.timeIntervalSince(last) >= interval
    }
}
```

- [ ] **Step 4: Failing service tests** (fake `NoteVaultIO` map, in-memory container listing ALL app models + `NoteIndexEntry`, pinned `now`):

```swift
import XCTest
import SwiftData
@testable import MustardKit

private final class FakeNoteIO: NoteVaultIO {
    var files: [String: String]
    var mtimes: [String: Date] = [:]
    init(_ files: [String: String]) { self.files = files }
    func notePaths() -> [String] { files.keys.sorted() }
    func read(_ p: String) -> String? { files[p] }
    func write(_ p: String, _ c: String) throws { files[p] = c }
    func snapshot(_ p: String, _ c: String) throws {}
    func modificationDate(_ p: String) -> Date? { mtimes[p] }
}

@MainActor
final class NoteIndexServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, Recommendation.self,
            CalendarEvent.self, NoteIndexEntry.self, configurations: config))
    }
    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    func test_reindex_buildsEntries_titleTagsLinksSnapshot() throws {
        let ctx = try makeContext()
        let io = FakeNoteIO([
            "Home.md": "---\ntags: [hub]\n---\n# Home\ngo [[Setup]]",
            "guides/Setup.md": "# Setup",
        ])
        io.mtimes["Home.md"] = t0
        let svc = NoteIndexService(context: ctx, makeIO: { _ in io })
        svc.reindex(project: "KB", workingDirectory: "/kb", now: t0)
        let entries = try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).sorted { $0.relativePath < $1.relativePath }
        XCTAssertEqual(entries.map(\.relativePath), ["Home.md", "guides/Setup.md"])
        XCTAssertEqual(entries[0].title, "Home")
        XCTAssertEqual(entries[0].tags, ["hub"])
        XCTAssertEqual(entries[0].forwardLinks, ["guides/Setup.md"])
        XCTAssertEqual(entries[0].lastModified, t0)
        XCTAssertEqual(entries[0].project, "KB")
        XCTAssertTrue(entries[0].contentSnapshot.contains("[[Setup]]"))
    }

    func test_reindex_isWholesale_removesDeletedFiles_leavesOtherProjects() throws {
        let ctx = try makeContext()
        ctx.insert(NoteIndexEntry(project: "KB", relativePath: "gone.md"))
        ctx.insert(NoteIndexEntry(project: "Other", relativePath: "keep.md"))
        let svc = NoteIndexService(context: ctx, makeIO: { _ in FakeNoteIO(["new.md": "# N"]) })
        svc.reindex(project: "KB", workingDirectory: "/kb", now: t0)
        let paths = try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).map { "\($0.project)/\($0.relativePath)" }.sorted()
        XCTAssertEqual(paths, ["KB/new.md", "Other/keep.md"])
    }

    func test_reindexDueProjects_respectsThrottle_andSkipsDisabled() throws {
        let ctx = try makeContext()
        let io = FakeNoteIO(["a.md": "# A"])
        let svc = NoteIndexService(context: ctx, makeIO: { _ in io })
        let settings = SourceSettings(sources: [
            SourceConfig(id: .vault, project: "KB", enabled: true, workingDirectory: "/kb"),
            SourceConfig(id: .vault, project: "Off", enabled: false, workingDirectory: "/off"),
        ], state: [])
        svc.reindexDueProjects(settings, now: t0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).map(\.project), ["KB"])
        io.files["b.md"] = "# B"
        svc.reindexDueProjects(settings, now: t0.addingTimeInterval(60))    // throttled — no change
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).count, 1)
        svc.reindexDueProjects(settings, now: t0.addingTimeInterval(301))   // due again
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).count, 2)
    }
}
```

- [ ] **Step 5: Implement `Agent/NoteIndexService.swift`:**

```swift
import Foundation
import SwiftData
import Observation

/// Rebuilds the per-project NoteIndexEntry mirror from the vault (BAK-148). Pure
/// filesystem work — no claude, no cost — so it can run every few minutes plus
/// immediately after an editor save. Wholesale rebuild per project (spec: vaults
/// are hundreds of files; avoids stale-edge bugs from incremental patching).
@MainActor
@Observable
public final class NoteIndexService {
    public private(set) var isIndexing = false
    public private(set) var lastIndexedAt: [String: Date] = [:]   // project → time (in-memory throttle)

    private let context: ModelContext
    private let makeIO: (String) -> NoteVaultIO

    public init(context: ModelContext,
                makeIO: @escaping (String) -> NoteVaultIO = { FileVaultIO(rootPath: $0) }) {
        self.context = context
        self.makeIO = makeIO
    }

    /// 60s-loop entry point: reindex every enabled project whose throttle has lapsed.
    public func reindexDueProjects(_ settings: SourceSettings, now: Date = .now) {
        for config in settings.sources where config.enabled && !config.workingDirectory.isEmpty {
            guard NoteReindexScheduler.isDue(lastIndexedAt: lastIndexedAt[config.project], now: now) else { continue }
            reindex(project: config.project, workingDirectory: config.workingDirectory, now: now)
        }
    }

    /// Wholesale rebuild of one project's entries. Also the on-save hook.
    public func reindex(project: String, workingDirectory: String, now: Date = .now) {
        isIndexing = true
        defer { isIndexing = false }
        let io = makeIO(workingDirectory)
        let docs = io.notePaths().compactMap { path -> (String, String)? in
            io.read(path).map { (path, $0) }
        }
        let index = WikilinkIndex.build(docs)
        let existing = (try? context.fetch(FetchDescriptor<NoteIndexEntry>())) ?? []
        for entry in existing where entry.project == project { context.delete(entry) }
        for note in index.notes {
            context.insert(NoteIndexEntry(
                project: project, relativePath: note.relativePath, title: note.title,
                tags: note.tags, lastModified: io.modificationDate(note.relativePath) ?? .distantPast,
                forwardLinks: index.forwardLinks[note.relativePath] ?? [],
                contentSnapshot: docs.first { $0.0 == note.relativePath }?.1 ?? ""))
        }
        try? context.save()
        lastIndexedAt[project] = now
    }
}
```

- [ ] **Step 6: Run** — both new suites PASS; full `swift test`.
- [ ] **Step 7: Registration + wiring** (build-verified, no unit tests):
  - `MustardContainer.make()` and `PreviewData.container`: append `NoteIndexEntry.self` to the `ModelContainer(for:)` lists. In `PreviewData`, insert two sample entries (e.g. `Home.md` linking to `guides/Setup.md`, project `"DL-Knowledge-Base"`) for previews.
  - `MustardApp`: add `@State private var noteIndex: NoteIndexService`, init with `container.mainContext`, `.environment(noteIndex)` on `RootView`; inside the 60s loop (after the sweep block, unguarded by `isSweeping` — it's cheap and local): `noteIndex.reindexDueProjects(SourceSettingsStore.loadOrMigrate())`.
  - `CommandBarEngine`: add `case goNotes` and `case reindexNotes` to `CommandKind`; add items `CommandItem(id: "notes", title: "Go to Notes", icon: "doc.text", kind: .goNotes)` and `CommandItem(id: "reindex", title: "Reindex notes now", icon: "arrow.clockwise", kind: .reindexNotes)`. Extend `Tests/MustardTests/CommandBarEngineTests.swift` if it exists (check; add coverage for the two new items appearing in the unfiltered list).
  - `CommandBarView`: handle both kinds — `goNotes` sets `screen = .notes` (the case lands in Task 5; to keep this task buildable, add the `MustardScreen.notes` case HERE with `systemImage: "doc.text"`, insert into `MustardScreen.primary` between `.week` and `.agent`, and give `RootView`'s `switch` a temporary `case .notes: Text("Notes — coming in BAK-149").font(Theme.Fonts.body)` placeholder). `reindexNotes` calls `noteIndex.reindexDueProjects` with a forced pass — add a `public func reindexAll(_ settings: SourceSettings)` convenience that ignores the throttle (loops `reindex(project:workingDirectory:)` directly).
- [ ] **Step 8: Run** — full `swift test` + `swift build` → green.
- [ ] **Step 9: Commit** — `feat(notes): NoteIndexEntry model, NoteIndexService reindex + loop/⌘K wiring (BAK-148)`

---

### Task 5: Notes tab — sidebar, folder tree, filter (BAK-149)

**Files:**
- Create: `Sources/MustardKit/Logic/NoteTree.swift`, `Tests/MustardTests/NoteTreeTests.swift`
- Create: `Sources/MustardKit/Views/NotesView.swift`
- Modify: `Sources/MustardKit/Views/RootView.swift` (replace Task 4's placeholder with `NotesView()`)

- [ ] **Step 1: Failing `NoteTree` tests** — pure paths→tree + filter:

```swift
import XCTest
@testable import MustardKit

final class NoteTreeTests: XCTestCase {
    private let notes: [(relativePath: String, title: String)] = [
        ("readme.md", "Readme"),
        ("guides/setup.md", "Setup"),
        ("guides/deep/adv.md", "Advanced"),
        ("meetings/sync.md", "Weekly Sync"),
    ]

    func test_build_nestsFoldersAndSortsNotes() {
        let root = NoteTree.build(notes)
        XCTAssertEqual(root.notes.map(\.relativePath), ["readme.md"])
        XCTAssertEqual(root.subfolders.map(\.name), ["guides", "meetings"])
        XCTAssertEqual(root.subfolders[0].subfolders.map(\.name), ["deep"])
        XCTAssertEqual(root.subfolders[0].notes.map(\.title), ["Setup"])
    }
    func test_filter_matchesTitleOrFilename_caseInsensitive_prunesEmptyFolders() {
        let root = NoteTree.build(notes)
        let filtered = NoteTree.filter(root, query: "setup")
        XCTAssertEqual(filtered.subfolders.count, 1)
        XCTAssertEqual(filtered.subfolders[0].notes.map(\.relativePath), ["guides/setup.md"])
        XCTAssertTrue(filtered.notes.isEmpty)
        let byTitle = NoteTree.filter(root, query: "weekly")
        XCTAssertEqual(byTitle.subfolders.map(\.name), ["meetings"])
    }
    func test_filter_emptyQuery_returnsTreeUnchanged() {
        let root = NoteTree.build(notes)
        XCTAssertEqual(NoteTree.filter(root, query: "  "), root)
    }
}
```

- [ ] **Step 2: Run → FAIL. Step 3: Implement `Logic/NoteTree.swift`:**

```swift
import Foundation

public struct NoteTreeLeaf: Equatable, Identifiable {
    public let relativePath: String
    public let title: String
    public var id: String { relativePath }
    public var filename: String { (relativePath as NSString).lastPathComponent }
}

public struct NoteTreeFolder: Equatable, Identifiable {
    public let path: String            // "" for root, "guides", "guides/deep"
    public var name: String { path.isEmpty ? "" : (path as NSString).lastPathComponent }
    public var subfolders: [NoteTreeFolder]
    public var notes: [NoteTreeLeaf]
    public var id: String { path }
}

/// Pure path-list → folder tree for the Notes sidebar (BAK-149), plus the
/// filename/title filter box. Folders and notes are sorted case-insensitively.
public enum NoteTree {
    public static func build(_ notes: [(relativePath: String, title: String)]) -> NoteTreeFolder
    public static func filter(_ root: NoteTreeFolder, query: String) -> NoteTreeFolder
}
```

`build`: group by first path component recursively (or build a dictionary of folder-path → leaves then assemble). `filter`: trimmed-empty query → unchanged; else depth-first keep leaves where `title` or `filename` `localizedCaseInsensitiveContains(query)`, keep folders with any surviving descendant.

- [ ] **Step 4: Run → PASS. Full suite green. Commit** — `feat(notes): NoteTree sidebar model (BAK-149 logic)`

- [ ] **Step 5: `NotesView`** — layout mirrors `RootView`'s calm style, all tokens from `Theme`:

```swift
public struct NoteRef: Equatable, Hashable {
    public let project: String
    public let workingDirectory: String
    public let relativePath: String
}

public struct NotesView: View {
    @Query private var entries: [NoteIndexEntry]
    @State private var selected: NoteRef?
    @State private var filter = ""
    @Environment(NoteIndexService.self) private var noteIndex
    // sources read once per body from SourceSettingsStore.loadOrMigrate().sources.filter(\.enabled)
}
```

Structure: `HStack(spacing: 0)` → notes sidebar (~230pt, `Theme.Palette.sidebar` background) `Divider().overlay(Theme.Palette.hairline)` → detail. Sidebar: filter `TextField` (magnifying-glass icon, `Theme.Fonts.meta`) at top; below, a `ScrollView` with one section per enabled `SourceConfig`: project name header (`Theme.Fonts.meta`, `textTertiary`, uppercase-small like `AreaSidebarSection` — read that file and mirror its header treatment), then the folder tree from `NoteTree.build(entries for that project)` filtered by `filter`, rendered recursively with `DisclosureGroup` (folder rows: folder icon + name, `Theme.Fonts.body`; leaf rows: `doc.text` icon + title, selected row uses `Theme.Palette.surface` rounded background exactly like RootView's sidebar buttons). Leaf tap sets `selected`. Detail pane: placeholder `VStack` (`Text("Select a note")`, `Theme.Fonts.body`, `textTertiary`, centered) — the editor lands in Task 6.

Empty state: no enabled sources → centered hint "Add a project in Agent → Sources to browse notes."

- [ ] **Step 6: Replace the RootView placeholder** with `case .notes: NotesView()`.
- [ ] **Step 7: `swift build` + full `swift test` → green. Commit** — `feat(notes): Notes tab with project sidebar, folder tree, filter (BAK-149)`

---

### Task 6: Note editor — source/preview + save-to-vault (BAK-150)

**Files:**
- Create: `Sources/MustardKit/Views/NoteEditorView.swift`, `Sources/MustardKit/Views/MarkdownPreviewView.swift`
- Modify: `Sources/MustardKit/Views/NotesView.swift` (detail pane hosts the editor)

No new logic — parsing came from Tasks 2/3; save IO is `NoteVaultIO` (already tested). Views are build-verified.

- [ ] **Step 1: `NoteEditorView`.** Props: `ref: NoteRef`, `onNavigate: (NoteRef) -> Void` (used in Task 9; wire a no-op now). State: `@State text: String`, `@State diskText: String` (content at load, for dirty check + snapshot), `@State mode: EditorMode` (`enum EditorMode { case source, preview }`), `@Environment(NoteIndexService.self)`.
  - Load on `.task(id: ref)`: `FileVaultIO(rootPath: ref.workingDirectory).read(ref.relativePath)` → both `text` and `diskText`. Missing file → calm error text.
  - Header row: note title (`Theme.Fonts.header`), spacer, dirty dot (`circle.fill` 6pt `Theme.Palette.warning`) when `text != diskText`, a `Picker` (`.segmented`) Source/Preview, and a Save button (`.keyboardShortcut("s", modifiers: .command)`), disabled when clean.
  - Source mode: `TextEditor(text: $text)` with `.font(.system(size: 13, design: .monospaced))`, `foregroundStyle(Theme.Palette.textPrimary)`, `scrollContentBackground(.hidden)`, `Theme.Palette.bg` background, comfortable padding. (Plain — syntax cues descoped to Phase C, spec addendum #3.)
  - Preview mode: `MarkdownPreviewView(body:onWikilinkTap:)` fed `Frontmatter.parse(text).body`; frontmatter itself is not rendered in preview.
  - Save (button or ⌘S): snapshot-then-write per addendum #5 —
    ```swift
    let io = FileVaultIO(rootPath: ref.workingDirectory)
    if let prior = io.read(ref.relativePath) { try? io.snapshot(ref.relativePath, prior) }
    try? io.write(ref.relativePath, text)
    diskText = text
    noteIndex.reindex(project: ref.project, workingDirectory: ref.workingDirectory)
    ```
  - Save-on-switch: `.onChange(of: ref)` — if dirty, run the same save with the *previous* ref (capture old value from the onChange arguments) so switching notes never drops edits.
- [ ] **Step 2: `MarkdownPreviewView`.** Props: `body: String`, `resolve: (String) -> NoteRef?` (nil-returning stub until Task 9), `onWikilinkTap: (String) -> Void`. Render `MarkdownBlocks.parse(body)` in a `ScrollView` / `LazyVStack(alignment: .leading, spacing: 10)`:
  - heading: size 22/18/15.5 for levels 1/2/≥3, `.medium`, `textPrimary`, extra top padding.
  - paragraph/quote/bullet/ordered runs: build one `Text` by concatenation — `.text` runs via `Text(AttributedString(inlineMarkdown: run))` helper: `(try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)`; `.wikilink` runs as `Text(alias ?? target)` in `Theme.Palette.accent` (underline). Tap handling for mixed Text: wrap the whole block's wikilinks using `.environment(\.openURL, OpenURLAction { ... })` + `AttributedString.link = URL(string: "mustard-note://\(target)")` — i.e. embed each wikilink run as a link attribute, intercept via `OpenURLAction`, call `onWikilinkTap(target)`, return `.handled`. (This gives real tap targets inside flowing text without custom layout.)
  - bullet: `HStack(alignment: .firstTextBaseline)` with "•" (`textTertiary`) and indent `CGFloat(indent) * 16`; ordered: same with "·" or the number if captured.
  - quote: leading 2pt `Theme.Palette.hairline` bar + `onSurfaceSoft` text.
  - code: `Text(code)` monospaced 12.5, `Theme.Palette.surface` rounded background, horizontal scroll not needed (wrap).
  - rule: `Divider().overlay(Theme.Palette.hairline)`.
- [ ] **Step 3: Host in `NotesView`** detail pane: `if let selected { NoteEditorView(ref: selected, onNavigate: { selected = $0 }) }`.
- [ ] **Step 4: `swift build` + full `swift test` → green. Commit** — `feat(notes): raw-markdown editor with Source/Preview toggle + snapshot-guarded save (BAK-150)`

---

### Task 7: Backlinks panel (BAK-151)

**Files:**
- Create: `Sources/MustardKit/Logic/BacklinkSnippets.swift`, `Tests/MustardTests/BacklinkSnippetsTests.swift`
- Create: `Sources/MustardKit/Views/BacklinksPanel.swift`
- Modify: `Sources/MustardKit/Views/NoteEditorView.swift` (mount panel below editor)

The index stores `forwardLinks` (resolved paths) but not the containing line — the panel recovers the snippet from the linking note's `contentSnapshot` with a pure helper.

- [ ] **Step 1: Failing tests:**

```swift
import XCTest
@testable import MustardKit

final class BacklinkSnippetsTests: XCTestCase {
    func test_snippet_firstLineWhoseWikilinkResolvesToTarget() {
        let content = "intro\nsee [[Setup]] here\nlater [[Other]]"
        let s = BacklinkSnippets.snippet(
            in: content, targetPath: "guides/Setup.md", candidatePaths: ["guides/Setup.md", "Other.md"])
        XCTAssertEqual(s, "see [[Setup]] here")
    }
    func test_snippet_aliasAndPathQualifiedLinksStillMatch() {
        XCTAssertEqual(BacklinkSnippets.snippet(
            in: "x [[guides/Setup|the guide]] y", targetPath: "guides/Setup.md",
            candidatePaths: ["guides/Setup.md"]), "x [[guides/Setup|the guide]] y")
    }
    func test_snippet_noMatch_returnsNil() {
        XCTAssertNil(BacklinkSnippets.snippet(in: "no links", targetPath: "A.md", candidatePaths: ["A.md"]))
    }
}
```

- [ ] **Step 2: Run → FAIL. Step 3: Implement** — reuse Task 2's extraction: scan body lines (skip fences), for each wikilink occurrence `WikilinkIndex.resolve(target:in:candidatePaths)`, return first line resolving to `targetPath`; nil otherwise. Trim the returned line.
- [ ] **Step 4: Run → PASS. Commit** — `feat(notes): backlink snippet extraction (BAK-151 logic)`
- [ ] **Step 5: `BacklinksPanel` view.** Props: `current: NoteRef`, `entries: [NoteIndexEntry]` (same-project, passed from NotesView's @Query), `onNavigate: (NoteRef) -> Void`. Compute `linkers = entries.filter { $0.forwardLinks.contains(current.relativePath) }` sorted by title. Render a `DisclosureGroup` (default expanded, persist collapse in `@AppStorage("notesBacklinksExpanded")`): header "Backlinks · N" (`Theme.Fonts.meta`, `textSecondary`); rows: title (`Theme.Fonts.body`, `accent`-tinted on hover) + snippet from `BacklinkSnippets.snippet(in: linker.contentSnapshot, targetPath: current.relativePath, candidatePaths: entries.map(\.relativePath))` (`Theme.Fonts.meta`, `textSecondary`, 1-line truncation). Row tap → `onNavigate`. Empty: "No backlinks yet" in `textTertiary`. Mount below the editor inside `NoteEditorView` (above a hairline divider), only when entries exist for the project.
- [ ] **Step 6: `swift build` + full suite. Commit** — `feat(notes): collapsible backlinks panel with snippets (BAK-151)`

---

### Task 8: New note creation "+" (BAK-153)

**Files:**
- Create: `Sources/MustardKit/Logic/NoteCreation.swift`, `Tests/MustardTests/NoteCreationTests.swift`
- Modify: `Sources/MustardKit/Views/NotesView.swift` ("+" button + sheet)

- [ ] **Step 1: Failing tests:**

```swift
import XCTest
@testable import MustardKit

final class NoteCreationTests: XCTestCase {
    func test_relativePath_landsInNotesFolder_sanitized() {
        XCTAssertEqual(NoteCreation.relativePath(title: "My: Plan/Idea", existing: []),
                       "notes/My- Plan-Idea.md")
    }
    func test_relativePath_collision_appendsCounter_caseInsensitive() {
        XCTAssertEqual(NoteCreation.relativePath(title: "Setup", existing: ["notes/setup.md"]),
                       "notes/Setup 2.md")
        XCTAssertEqual(NoteCreation.relativePath(title: "Setup", existing: ["notes/Setup.md", "notes/Setup 2.md"]),
                       "notes/Setup 3.md")
    }
    func test_relativePath_emptyTitle_defaultsUntitled() {
        XCTAssertEqual(NoteCreation.relativePath(title: "  ", existing: []), "notes/Untitled.md")
    }
    func test_stub_hasFrontmatterAndHeading() {
        XCTAssertEqual(NoteCreation.stub(title: "My Note"),
                       "---\ntitle: My Note\ntags: []\n---\n\n# My Note\n")
    }
}
```

- [ ] **Step 2: Run → FAIL. Step 3: Implement `Logic/NoteCreation.swift`:** sanitize title by replacing `/:\\` with `-` and trimming; empty → "Untitled"; collision check case-insensitively against `existing` (full relative paths), counter suffix ` 2`, ` 3`…; `stub` exactly as asserted (Phase B's `task_id`/`area` land in this frontmatter later).
- [ ] **Step 4: Run → PASS. Commit** — `feat(notes): NoteCreation filename + stub rules (BAK-153 logic)`
- [ ] **Step 5: Wire the "+".** In `NotesView` sidebar, per-project header gets a trailing `plus` icon button (visible on hover or always, `textTertiary` → `accent` on hover). Tap → small sheet/popover: `TextField("Note title")` + Create button. Create:
    ```swift
    let io = FileVaultIO(rootPath: config.workingDirectory)
    let rel = NoteCreation.relativePath(title: title, existing: io.notePaths())
    try? io.write(rel, NoteCreation.stub(title: title))   // FileVaultIO.write needs parent dir — create "notes/" first via FileManager if missing
    noteIndex.reindex(project: config.project, workingDirectory: config.workingDirectory)
    selected = NoteRef(project: config.project, workingDirectory: config.workingDirectory, relativePath: rel)
    ```
    **Check `FileVaultIO.write`** — it does NOT create intermediate directories. Add directory creation to the write path in `FileVaultIO.write` (safe for all callers — meeting notes always exist) rather than in the view: `try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)` before writing. Add a temp-dir test in `FileVaultIOTests`: `test_write_createsIntermediateDirectories`.
- [ ] **Step 6: `swift build` + full suite. Commit** — `feat(notes): "+" new note into project notes/ with frontmatter stub (BAK-153)`

---

### Task 9: Wikilink navigation + create-from-unresolved (BAK-152)

**Files:**
- Modify: `Sources/MustardKit/Views/NotesView.swift`, `Sources/MustardKit/Views/NoteEditorView.swift`, `Sources/MustardKit/Views/MarkdownPreviewView.swift`

All resolution logic already exists (`WikilinkIndex.resolve`, Task 2) — this is wiring.

- [ ] **Step 1: Resolve + navigate.** In `NotesView`, pass the editor a resolver closure over the current project's entries:
    ```swift
    let paths = entries.filter { $0.project == selected.project }.map(\.relativePath)
    // in onWikilinkTap(target):
    if let hit = WikilinkIndex.resolve(target: target, in: paths) {
        selected = NoteRef(project: ..., workingDirectory: ..., relativePath: hit)
    } else { pendingCreateTarget = target }   // @State — drives the offer alert
    ```
    Preview styles resolved links `Theme.Palette.accent`; unresolved ones `Theme.Palette.textTertiary` with underline (uses the same resolver via the `resolve` prop from Task 6 — replace the stub).
- [ ] **Step 2: Create-from-unresolved.** `.alert("Create note “\(target)”?", isPresented: ...)` with Create/Cancel. Create reuses Task 8's flow verbatim (`NoteCreation.relativePath(title: target, ...)` into the current note's project) and navigates to the new note.
- [ ] **Step 3: Save-before-navigate.** Navigation goes through selection change; Task 6's save-on-switch already covers dirty edits — verify that path handles wikilink navigation too (same `.onChange(of: ref)`).
- [ ] **Step 4: `swift build` + full `swift test`. Commit** — `feat(notes): wikilink click-to-navigate + create-from-unresolved-link (BAK-152)`

---

### Task 10: Finish line

- [ ] Full `swift test` (expect ~73 pre-existing + ~30 new, all green) and `swift build`; `./build-app.sh` to confirm the app assembles.
- [ ] Update `CLAUDE.md` folder-layout block: add `WikilinkIndex, MarkdownBlocks, NoteTree, NoteCreation, NoteReindexScheduler, BacklinkSnippets` to Logic/, `NoteIndexService` + `NoteVaultIO` note to Agent/, `NoteIndexEntry` to Models/, Notes views to Views/.
- [ ] Update `docs/build-order.md` if it tracks phases (add Notes Phase A as shipped).
- [ ] PR to `main` titled `feat(notes): Notes Phase A — vault-backed markdown notes with wikilinks & backlinks (BAK-145)`, body linking the spec + epic; fresh-context review per `.agent-loop/review-rubric.md`; merge per `.agent-loop` policy; digest entry with revert line.
- [ ] Linear: BAK-146…153 → Done, BAK-145 → Done, with a closing comment linking the PR.

## Self-review notes

- Spec coverage: scanner→T1, WikilinkIndex→T2, preview→T3/T6, model+reindex(schedule/save/manual)→T4, tab/sidebar/tree/filter→T5, editor+save→T6, backlinks→T7, creation→T8, navigation→T9. Mobile story = model registration only (T4) — matches spec (no code path until N2). Addendum items all placed (#1 T4, #2 T4, #3 T6, #4 T3/T6, #5 T6, #6 T2).
- Types used across tasks: `NoteRef` defined T5, used T6/T7/T9. `NoteVaultIO` defined T1, used T4/T6/T8. `WikilinkIndex.resolve` signature identical T2/T7/T9. `EditorMode` local to T6.
- Known intentional choices: backlink snippet recovered from `contentSnapshot` (not stored per-edge) — avoids a bigger model; `lastIndexedAt` in-memory only (reindex-on-launch is desired anyway); `hub` pruned from notes enumeration (Mustard scratch).
