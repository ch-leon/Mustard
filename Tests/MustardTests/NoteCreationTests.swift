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
    func test_relativePath_backslashSanitized() {
        XCTAssertEqual(NoteCreation.relativePath(title: "a\\b", existing: []), "notes/a-b.md")
    }
    func test_stub_emptyTitle_defaultsUntitled() {
        XCTAssertEqual(NoteCreation.stub(title: "   "),
                       "---\ntitle: Untitled\ntags: []\n---\n\n# Untitled\n")
    }

    // MARK: - Hardening (review follow-ups)

    func test_relativePath_leadingDots_stripped() {
        // notes/.hidden.md would be invisible to notePaths() (skipsHiddenFiles):
        // the note vanishes and the collision check can't see it.
        XCTAssertEqual(NoteCreation.relativePath(title: ".hidden", existing: []),
                       "notes/hidden.md")
        XCTAssertEqual(NoteCreation.relativePath(title: "...", existing: []),
                       "notes/Untitled.md")
    }

    func test_relativePath_longTitle_clampedUnderFilenameLimit() {
        let long = String(repeating: "a", count: 300)
        let first = NoteCreation.relativePath(title: long, existing: [])
        let filename = String(first.dropFirst("notes/".count))
        XCTAssertTrue(first.hasPrefix("notes/"))
        XCTAssertTrue(first.hasSuffix(".md"))
        XCTAssertLessThanOrEqual(filename.utf8.count, 255)
        // Truncation happens BEFORE the counter, so collisions never push it over.
        let second = NoteCreation.relativePath(title: long, existing: [first])
        XCTAssertEqual(second, String(first.dropLast(3)) + " 2.md")
        XCTAssertLessThanOrEqual(String(second.dropFirst("notes/".count)).utf8.count, 255)
    }

    func test_relativePath_longMultibyteTitle_truncatesOnCharacterBoundary() {
        let long = String(repeating: "é", count: 300)   // 2 UTF-8 bytes each
        let first = NoteCreation.relativePath(title: long, existing: [])
        let name = String(first.dropFirst("notes/".count).dropLast(".md".count))
        XCTAssertLessThanOrEqual(name.utf8.count, 200)
        XCTAssertTrue(name.allSatisfy { $0 == "é" })   // no split scalar
    }

    func test_stub_titleWithColon_quotedForYAML() {
        XCTAssertEqual(NoteCreation.stub(title: "Meeting: Notes"),
                       "---\ntitle: \"Meeting: Notes\"\ntags: []\n---\n\n# Meeting: Notes\n")
    }

    func test_stub_quotedTitle_roundTripsThroughFrontmatterParse() {
        let parsed = Frontmatter.parse(NoteCreation.stub(title: "Meeting: Notes"))
        XCTAssertEqual(parsed.title, "Meeting: Notes")
    }

    func test_stub_titleStartingWithDash_quoted() {
        XCTAssertEqual(NoteCreation.stub(title: "- draft"),
                       "---\ntitle: \"- draft\"\ntags: []\n---\n\n# - draft\n")
    }

    func test_stub_titleWithHash_quoted() {
        XCTAssertEqual(NoteCreation.stub(title: "C# tips"),
                       "---\ntitle: \"C# tips\"\ntags: []\n---\n\n# C# tips\n")
    }

    func test_stub_internalQuotesAndBackslashes_escaped() {
        XCTAssertEqual(NoteCreation.stub(title: #"say "hi" \o/"#),
                       "---\ntitle: \"say \\\"hi\\\" \\\\o/\"\ntags: []\n---\n\n# say \"hi\" \\o/\n")
    }

    func test_titleNewlines_foldedToSingleSpaces() {
        // Multi-line paste must not corrupt the frontmatter or heading.
        XCTAssertEqual(NoteCreation.stub(title: "Line one\n\nLine two"),
                       "---\ntitle: Line one Line two\ntags: []\n---\n\n# Line one Line two\n")
        XCTAssertEqual(NoteCreation.relativePath(title: "Line one\nLine two", existing: []),
                       "notes/Line one Line two.md")
    }

    func test_singleOverBudgetGraphemeCluster_fallsBackToUntitled() {
        // One grapheme cluster larger than the whole 200-byte budget clamps to ""
        // — without the post-clamp fallback that would create hidden "notes/.md".
        let zalgo = "e" + String(repeating: "\u{0301}", count: 110)   // one Character, 221 UTF-8 bytes
        XCTAssertEqual(NoteCreation.relativePath(title: zalgo, existing: []), "notes/Untitled.md")
    }
}
