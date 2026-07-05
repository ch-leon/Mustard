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
    /// A note whose first heading is a sub-level (## …) must title from that
    /// heading, matching NoteEditorView's header (which scans #{1,6}). Before this
    /// unification the editor showed "Foo" but the sidebar showed the filename.
    func test_title_usesAnyHeadingLevel_notJustH1() {
        let idx = WikilinkIndex.build([
            ("a.md", "## Foo\nbody"),
            ("b.md", "###### Deep\nbody"),
        ])
        XCTAssertEqual(idx.notes.map(\.title), ["Foo", "Deep"])
    }
    /// Seven+ hashes or no trailing space is not a heading — falls back to filename.
    func test_title_sevenHashesIsNotHeading_fallsBackToFilename() {
        let idx = WikilinkIndex.build([("note.md", "####### too many\nbody")])
        XCTAssertEqual(idx.notes.map(\.title), ["note"])
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
    /// A path-qualified target with no exact-path match falls back to filename
    /// matching on its LAST component (Obsidian behavior) — load-bearing for
    /// create-from-unresolved (BAK-152): creating "Setup" from a tapped
    /// [[guides/Setup]] must satisfy the link, or it dangles forever.
    func test_resolve_pathQualified_noExactMatch_fallsBackToFilename() {
        XCTAssertEqual(WikilinkIndex.resolve(target: "guides/Setup", in: ["notes/Setup.md"]),
                       "notes/Setup.md")
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
        XCTAssertNil(idx.backlinks["a.md"])   // keys only exist for notes WITH backlinks
    }

    // MARK: Edge cases (added — never weaken the above)
    func test_build_emptyDocs_isEmpty() {
        let idx = WikilinkIndex.build([])
        XCTAssertEqual(idx.notes, []); XCTAssertEqual(idx.forwardLinks, [:]); XCTAssertEqual(idx.backlinks, [:])
    }
    func test_emptyTarget_isNotALink() {
        let idx = WikilinkIndex.build([("a.md", "empty [[]] and [[ ]] here")])
        XCTAssertEqual(idx.notes[0].links, [])
        XCTAssertNil(idx.forwardLinks["a.md"])
    }
    func test_selfLink_resolvesAndBacklinksToSelf() {
        let idx = WikilinkIndex.build([("a.md", "I link to [[a]] myself")])
        XCTAssertEqual(idx.forwardLinks["a.md"], ["a.md"])
        XCTAssertEqual(idx.backlinks["a.md"], [Backlink(sourcePath: "a.md", snippet: "I link to [[a]] myself")])
    }
    func test_notes_sortedByRelativePath() {
        let idx = WikilinkIndex.build([("z.md", "x"), ("a.md", "y"), ("m/b.md", "z")])
        XCTAssertEqual(idx.notes.map(\.relativePath), ["a.md", "m/b.md", "z.md"])
    }
    func test_frontmatter_strippedFromBody_andNotScannedForLinks() {
        // A wikilink sitting in the frontmatter block must not become a forward link.
        let idx = WikilinkIndex.build([
            ("a.md", "---\ntitle: [[Ghost]]\n---\nreal [[Target]]"), ("Target.md", "x"),
        ])
        XCTAssertEqual(idx.forwardLinks["a.md"], ["Target.md"])
    }
    func test_duplicateOccurrence_dedupedInBacklinks() {
        let idx = WikilinkIndex.build([
            ("a.md", "[[Home]] then [[Home]] on one line"), ("Home.md", "x"),
        ])
        // Same (source, snippet) collapses to one backlink.
        XCTAssertEqual(idx.backlinks["Home.md"], [Backlink(sourcePath: "a.md", snippet: "[[Home]] then [[Home]] on one line")])
    }
}
