import XCTest
@testable import MustardKit

final class NoteDecorationTests: XCTestCase {

    // MARK: - Blocks: the round-trip guard

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
    func test_blocks_fixtureBattery_lossless() {
        for source in [
            "- a\n  - nested\n    - deeper\n- b\n",
            "> one\n> two\n\n> three",
            "---\n\n***\n\ntext\n---\n",
            "```\nunterminated fence\n\nstill code",
            "\n\nleading blanks\n",
            "\n\n\n",
            "---",
            "---\r\ntitle: x\r\n---\r\nbody\r\n",
            "***",
            "# H\n#not-a-heading\n####### seven\n1) not ordered\n",
        ] {
            assertPartitionLossless(source)
        }
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
    func test_blocks_unterminatedFence_swallowsToEOF_flagged() {
        let blocks = NoteDecoration.blocks("```\ncode\n\n")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(blocks[0].isFence)
        assertPartitionLossless("```\ncode\n\n")
    }
    func test_blocks_headingQuoteListRuleLines_oneBlockPerLine() {
        // Single-line block kinds never group; the two plain lines do.
        let blocks = NoteDecoration.blocks("# H\n> q\n- a\n1. b\n---\npara\npara2")
        XCTAssertEqual(blocks.count, 6)
        assertPartitionLossless("# H\n> q\n- a\n1. b\n---\npara\npara2")
    }
    func test_blocks_leadingBlankLines_formTheirOwnBlock() {
        let source = "\n\npara"
        let ns = source as NSString
        let blocks = NoteDecoration.blocks(source)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(ns.substring(with: blocks[0].range), "\n\n")
        XCTAssertFalse(blocks[0].isFrontmatter)
        XCTAssertFalse(blocks[0].isFence)
    }
    func test_blocks_frontmatter_crlf_detected() {
        // \r\n terminators are excluded from the raw line compare (one terminator),
        // so CRLF frontmatter is detected exactly as Frontmatter.parse detects it.
        let blocks = NoteDecoration.blocks("---\r\ntitle: x\r\n---\r\nbody")
        XCTAssertTrue(blocks[0].isFrontmatter)
        XCTAssertEqual(blocks.count, 2)
    }

    // MARK: - Spans

    private typealias Span = NoteDecoration.Span

    func test_spans_heading_marksHashesAsMarker_textAsHeading() {
        let spans = NoteDecoration.spans("## Two")
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 0, length: 3), kind: .marker)))   // "## "
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 3, length: 3), kind: .heading(level: 2))))
    }
    func test_spans_bold_italic_code_withMarkerRanges() {
        // "a **b** *i* `c`" — b at 4, i at 9, c at 13.
        let spans = NoteDecoration.spans("a **b** *i* `c`")
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 4, length: 1), kind: .bold)))
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 2, length: 2), kind: .marker)))    // leading **
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 9, length: 1), kind: .italic)))
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 13, length: 1), kind: .inlineCode)))
    }
    func test_spans_wikilink_labelAndMarkers_aliasHidesTarget() {
        // "[[Note|alias]]" → markers: "[[", "Note|", "]]"; label: "alias"
        let spans = NoteDecoration.spans("[[Note|alias]]")
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 7, length: 5),
                                          kind: .wikilink(target: "Note", alias: "alias"))))
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 0, length: 2), kind: .marker)))
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 2, length: 5), kind: .marker)))    // "Note|"
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 12, length: 2), kind: .marker)))
    }
    func test_spans_wikilink_anchorIsMarker() {
        // "[[Note#Sec]]" → label "Note", "#Sec" de-emphasized.
        let spans = NoteDecoration.spans("[[Note#Sec]]")
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 2, length: 4),
                                          kind: .wikilink(target: "Note", alias: nil))))
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 6, length: 4), kind: .marker)))    // "#Sec"
    }
    func test_spans_embed_leadingBangInsideMarker() {
        // "![[Img]]" — the "!" is syntax, not label.
        let spans = NoteDecoration.spans("![[Img]]")
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 0, length: 3), kind: .marker)))    // "![["
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 3, length: 3),
                                          kind: .wikilink(target: "Img", alias: nil))))
    }
    func test_spans_noEmphasisInsideCodeSpan_orFence_orFrontmatter() {
        XCTAssertFalse(NoteDecoration.spans("`**x**`").contains { $0.kind == .bold })
        XCTAssertFalse(NoteDecoration.spans("```\n**x** [[L]]\n```").contains {
            $0.kind == .bold || $0.kind == .wikilink(target: "L", alias: nil)
        })
        XCTAssertFalse(NoteDecoration.spans("---\nnote: \"**x**\"\n---\n").contains { $0.kind == .bold })
    }
    func test_spans_wikilinkInsideInlineCode_staysRaw() {
        // Inline code is opaque, mirroring the fence rule one level down.
        let spans = NoteDecoration.spans("`[[L]]`")
        XCTAssertFalse(spans.contains { $0.kind == .wikilink(target: "L", alias: nil) })
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 1, length: 5), kind: .inlineCode)))
    }
    func test_spans_inBlock_matchesWholeDocumentSubset() {
        let source = "# H\n\npara **b**\n"
        let block = NoteDecoration.blocks(source)[1]
        XCTAssertEqual(NoteDecoration.spans(source, in: block),
                       NoteDecoration.spans(source).filter { block.range.contains($0.range.location) })
    }
    func test_spans_allRangesWithinBounds_neverOverlapContentKinds() {
        // Fixture battery: every span range fits in the source, and no two INLINE
        // content spans (bold/italic/code/wikilink) overlap. Line-level spans
        // (heading) deliberately cover their inline spans — layering, not overlap.
        func isInlineContent(_ kind: NoteDecoration.Kind) -> Bool {
            switch kind {
            case .bold, .italic, .inlineCode, .wikilink: return true
            default: return false
            }
        }
        for source in ["", "# H", "**a** *b* `c` [[w|x]]", "---\nt: v\n---\n# H\n```\nx\n```",
                       "- **a** [[L|l]] `x`\n> *q*"] {
            let ns = source as NSString
            let spans = NoteDecoration.spans(source)
            for span in spans {
                XCTAssertGreaterThanOrEqual(span.range.location, 0)
                XCTAssertLessThanOrEqual(span.range.upperBound, ns.length, "in \(source)")
            }
            let inline = spans.filter { isInlineContent($0.kind) }
            for (i, a) in inline.enumerated() {
                for b in inline.dropFirst(i + 1) {
                    XCTAssertEqual(NSIntersectionRange(a.range, b.range).length, 0,
                                   "\(a) overlaps \(b) in \(source)")
                }
            }
        }
    }
    func test_spans_listMarkers_bullet_ordered_quote_indent() {
        XCTAssertTrue(NoteDecoration.spans("- go [[Home]]").contains(
            Span(range: NSRange(location: 0, length: 2), kind: .listMarker)))
        XCTAssertTrue(NoteDecoration.spans("- go [[Home]]").contains(
            Span(range: NSRange(location: 7, length: 4), kind: .wikilink(target: "Home", alias: nil))))
        XCTAssertTrue(NoteDecoration.spans("1. first").contains(
            Span(range: NSRange(location: 0, length: 3), kind: .listMarker)))
        XCTAssertTrue(NoteDecoration.spans("> hi").contains(
            Span(range: NSRange(location: 0, length: 2), kind: .listMarker)))
        XCTAssertTrue(NoteDecoration.spans("  - a").contains(
            Span(range: NSRange(location: 0, length: 4), kind: .listMarker)))
    }
    func test_spans_fence_markerLinesAndCodeBlockInterior() {
        // "```swift\nlet a = 1\n```" — language tag rides in the marker line.
        let spans = NoteDecoration.spans("```swift\nlet a = 1\n```")
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 0, length: 8), kind: .marker)))
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 9, length: 10), kind: .codeBlock)))
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 19, length: 3), kind: .marker)))
    }
    func test_spans_emptyFence_hasNoCodeBlockSpan() {
        XCTAssertFalse(NoteDecoration.spans("```\n```").contains { $0.kind == .codeBlock })
    }
    func test_spans_frontmatter_isOneSpanOverWholeBlock() {
        let source = "---\nt: v\n---\n\nbody"
        let spans = NoteDecoration.spans(source, in: NoteDecoration.blocks(source)[0])
        XCTAssertEqual(spans, [Span(range: NSRange(location: 0, length: 14), kind: .frontmatter)])
    }
    func test_spans_ruleLines_deemphasizedAsMarker() {
        // A lone "---" has no closing fence, so it's a rule, not frontmatter.
        XCTAssertEqual(NoteDecoration.spans("---"),
                       [Span(range: NSRange(location: 0, length: 3), kind: .marker)])
        XCTAssertEqual(NoteDecoration.spans("***"),
                       [Span(range: NSRange(location: 0, length: 3), kind: .marker)])
    }
    func test_spans_headingWithInlineContent_layersBoth() {
        let spans = NoteDecoration.spans("# About [[Home]]")
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 2, length: 14), kind: .heading(level: 1))))
        XCTAssertTrue(spans.contains(Span(range: NSRange(location: 10, length: 4),
                                          kind: .wikilink(target: "Home", alias: nil))))
    }
    func test_spans_unmatchedMarkers_produceNoSpans() {
        // Raw text, never guessed.
        XCTAssertEqual(NoteDecoration.spans("**a"), [])
        XCTAssertEqual(NoteDecoration.spans("`x"), [])
        XCTAssertEqual(NoteDecoration.spans("a ** b"), [])
        XCTAssertEqual(NoteDecoration.spans("***bolditalic***"), [])
    }
    func test_spans_underscoreEmphasis_notParsed() {
        XCTAssertEqual(NoteDecoration.spans("_x_ and __y__"), [])
    }
    func test_spans_emptySource_isEmpty() {
        XCTAssertEqual(NoteDecoration.spans(""), [])
    }
}
