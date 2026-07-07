import XCTest
@testable import MustardKit

final class MarkdownBlocksTests: XCTestCase {
    func test_headings_levels() {
        XCTAssertEqual(MarkdownBlocks.parse("# One\n### Three"), [
            .heading(level: 1, runs: [.text("One")]),
            .heading(level: 3, runs: [.text("Three")]),
        ])
    }
    func test_crlf_normalized_headingParagraphAndRuleClean() {
        // \r\n must not leak into runs, and a `---\r\n` line is still a rule.
        XCTAssertEqual(MarkdownBlocks.parse("# One\r\nbody one\r\n\r\n---\r\nbody two"), [
            .heading(level: 1, runs: [.text("One")]),
            .paragraph(runs: [.text("body one")]),
            .rule,
            .paragraph(runs: [.text("body two")]),
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

    // MARK: - Edge cases (added, never weakening the above)

    func test_runs_emptyString_isEmptyRuns() {
        XCTAssertEqual(MarkdownBlocks.runs(""), [])
    }
    func test_runs_emptyTarget_isNotALink() {
        // "[[ ]]" has an empty-after-trim target — left as plain text.
        XCTAssertEqual(MarkdownBlocks.runs("a [[ ]] b"), [.text("a [[ ]] b")])
    }
    func test_runs_adjacentLinks_dropZeroLengthTextBetween() {
        XCTAssertEqual(MarkdownBlocks.runs("[[A]][[B]]"), [
            .wikilink(target: "A", alias: nil), .wikilink(target: "B", alias: nil),
        ])
    }
    func test_embed_treatedAsPlainWikilink() {
        // Leading "!" is consumed by the pattern, not left in the text run.
        XCTAssertEqual(MarkdownBlocks.runs("pre ![[Img]] post"), [
            .text("pre "), .wikilink(target: "Img", alias: nil), .text(" post"),
        ])
    }
    func test_runs_wikilinkWithHeading_stripsAnchor() {
        XCTAssertEqual(MarkdownBlocks.runs("[[Note#Section]]"), [
            .wikilink(target: "Note", alias: nil),
        ])
    }
    func test_headingLevel6_max() {
        XCTAssertEqual(MarkdownBlocks.parse("###### Six"), [
            .heading(level: 6, runs: [.text("Six")]),
        ])
    }
    func test_sevenHashes_isNotHeading() {
        // Seven "#" is not a valid heading — falls through to paragraph.
        XCTAssertEqual(MarkdownBlocks.parse("####### Seven"), [
            .paragraph(runs: [.text("####### Seven")]),
        ])
    }
    func test_asteriskRule() {
        XCTAssertEqual(MarkdownBlocks.parse("***"), [.rule])
    }
    func test_starBullet() {
        XCTAssertEqual(MarkdownBlocks.parse("* item"), [.bullet(runs: [.text("item")], indent: 0)])
    }
    func test_deepIndentBullet() {
        XCTAssertEqual(MarkdownBlocks.parse("      - deep"), [
            .bullet(runs: [.text("deep")], indent: 3),
        ])
    }
    func test_parenOrdered_isNotOrdered() {
        // "1)" is not treated as an ordered list — falls through to paragraph.
        XCTAssertEqual(MarkdownBlocks.parse("1) nope"), [
            .paragraph(runs: [.text("1) nope")]),
        ])
    }
    func test_unterminatedFence_capturesToEOF() {
        XCTAssertEqual(MarkdownBlocks.parse("```\nline one\nline two"), [
            .code("line one\nline two"),
        ])
    }
    func test_emptyFence_isEmptyCode() {
        XCTAssertEqual(MarkdownBlocks.parse("```\n```"), [.code("")])
    }
    func test_emptyBody_isNoBlocks() {
        XCTAssertEqual(MarkdownBlocks.parse(""), [])
    }
    func test_multipleBlanksBetweenParagraphs() {
        XCTAssertEqual(MarkdownBlocks.parse("a\n\n\nb"), [
            .paragraph(runs: [.text("a")]), .paragraph(runs: [.text("b")]),
        ])
    }
    func test_paragraphFlushedBeforeBlock() {
        XCTAssertEqual(MarkdownBlocks.parse("intro\n- bullet"), [
            .paragraph(runs: [.text("intro")]),
            .bullet(runs: [.text("bullet")], indent: 0),
        ])
    }
    func test_boldMarkersLeftInTextRun() {
        // Inline bold is NOT parsed here — view renders via AttributedString.
        XCTAssertEqual(MarkdownBlocks.runs("a **bold** b"), [.text("a **bold** b")])
    }
}
