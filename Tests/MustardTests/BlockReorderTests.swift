import XCTest
@testable import MustardKit

final class BlockReorderTests: XCTestCase {

    /// The safety invariant behind every move: no content line is ever lost,
    /// duplicated, or edited — the multiset of non-blank lines is preserved.
    /// (Blank-line SEPARATORS are the one thing `move` may adjust, byte-pinned
    /// in the fixtures below.)
    private func assertLineMultisetPreserved(_ source: String, _ moved: String,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let lines = { (s: String) in
            s.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .sorted()
        }
        XCTAssertEqual(lines(moved), lines(source), file: file, line: line)
    }

    // MARK: - Identity / out-of-range

    func test_move_identity_andOutOfRange_returnSourceByteIdentical() {
        let source = "# H\n\npara\n\n- a\n"
        XCTAssertEqual(BlockReorder.move(source, from: 1, to: 1), source)
        XCTAssertEqual(BlockReorder.move(source, from: 9, to: 0), source)
        XCTAssertEqual(BlockReorder.move(source, from: -1, to: 0), source)
        XCTAssertEqual(BlockReorder.move(source, from: 0, to: 9), source)
        XCTAssertEqual(BlockReorder.move(source, from: 0, to: -1), source)
    }
    func test_move_emptyAndFrontmatterOnlySources_unchanged() {
        XCTAssertEqual(BlockReorder.move("", from: 0, to: 1), "")
        let fmOnly = "---\ntitle: x\n---\n"
        XCTAssertEqual(BlockReorder.move(fmOnly, from: 0, to: 1), fmOnly)
    }

    // MARK: - Byte-pinned moves

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
    func test_move_frontmatterWithTrailingBlank_emittedVerbatim() {
        let source = "---\ntitle: x\n---\n\n# H\n\npara\n"
        let moved = BlockReorder.move(source, from: 1, to: 0)
        XCTAssertEqual(moved, "---\ntitle: x\n---\n\npara\n\n# H\n")
        assertLineMultisetPreserved(source, moved)
    }
    func test_move_lastBlockWithoutNewline_gainsSeparator_noLineLost() {
        let moved = BlockReorder.move("first\n\ntail no newline", from: 1, to: 0)
        XCTAssertEqual(moved, "tail no newline\n\nfirst\n")
        assertLineMultisetPreserved("first\n\ntail no newline", moved)
    }
    func test_move_quoteBlock_toFront_separatorsStayPositional() {
        let source = "para\n\n> quoted\n\ntail\n"
        XCTAssertEqual(BlockReorder.move(source, from: 1, to: 0),
                       "> quoted\n\npara\n\ntail\n")
    }
    func test_move_listLines_areIndividualBlocks() {
        // List lines partition one block per line (NoteDecoration rule) — a drag
        // moves a single list line, not the whole run.
        let source = "- a\n  - a1\n- b\n"
        XCTAssertEqual(BlockReorder.move(source, from: 0, to: 2),
                       "  - a1\n- b\n- a\n")
    }
    func test_move_ruleToEnd_midDocumentNoTerminatorBlock_gainsNewline() {
        // "two" had no trailing newline; landing mid-document it gains "\n" so it
        // can't fuse with the rule line.
        let source = "one\n\n---\n\ntwo"
        let moved = BlockReorder.move(source, from: 1, to: 2)
        XCTAssertEqual(moved, "one\n\ntwo\n\n---\n")
        assertLineMultisetPreserved(source, moved)
    }
    func test_move_crlf_blocks_preserveCRLFBytes() {
        let source = "# H\r\n\r\npara\r\n"
        XCTAssertEqual(BlockReorder.move(source, from: 1, to: 0),
                       "para\r\n\r\n# H\r\n")
    }

    // MARK: - Invariant battery

    func test_move_batteryOfSources_everyValidMove_preservesLineMultiset() {
        let sources = [
            "# H\n\npara one\npara two\n\n- a\n- b\n\n```\ncode [[x]]\n```\n",
            "---\ntitle: x\n---\n\n> q\n\n1. one\n\ntail",
            "a\r\n\r\nb\r\n\r\nc",
            "***\n\ntext\n\n***\n",
        ]
        for source in sources {
            let count = NoteDecoration.blocks(source).filter { !$0.isFrontmatter }.count
            for from in 0..<count {
                for to in 0..<count {
                    let moved = BlockReorder.move(source, from: from, to: to)
                    assertLineMultisetPreserved(source, moved)
                    if from == to { XCTAssertEqual(moved, source) }
                }
            }
        }
    }
}
