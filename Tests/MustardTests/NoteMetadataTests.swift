import XCTest
@testable import MustardKit

final class NoteMetadataTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private let now = Date(timeIntervalSince1970: 1_751_790_000)   // 2025-07-06 ~08:20 UTC

    func test_wordCount_stripsFrontmatter_countsBodyWords() {
        // "#" is bare syntax, not a word — 3, not 4.
        XCTAssertEqual(NoteMetadata.wordCount("---\ntitle: skip me\n---\n# Two words\n\none"), 3)
    }
    func test_wordCount_emptyAndWhitespaceOnly_isZero() {
        XCTAssertEqual(NoteMetadata.wordCount(""), 0)
        XCTAssertEqual(NoteMetadata.wordCount("---\nt: x\n---\n  \n"), 0)
    }
    func test_wordCount_syntaxOnlyTokens_dontCount() {
        XCTAssertEqual(NoteMetadata.wordCount("- [ ] task\n\n---\n\n**bold**"), 2)   // "task", "**bold**"
    }
    func test_line_editedToday_yesterday_andDated() {
        XCTAssertEqual(NoteMetadata.line(project: "KB", modified: now.addingTimeInterval(-3_600),
                                         wordCount: 2, now: now, calendar: cal),
                       "KB · edited today · 2 words")
        XCTAssertTrue(NoteMetadata.line(project: "KB", modified: now.addingTimeInterval(-86_400),
                                        wordCount: 1, now: now, calendar: cal).contains("edited yesterday"))
        XCTAssertEqual(NoteMetadata.line(project: "KB", modified: now.addingTimeInterval(-10 * 86_400),
                                         wordCount: 2, now: now, calendar: cal),
                       "KB · edited 26 Jun · 2 words")
    }
    func test_line_nilModified_omitsEditedSegment() {
        XCTAssertEqual(NoteMetadata.line(project: "KB", modified: nil, wordCount: 1, now: now, calendar: cal),
                       "KB · 1 word")
    }
    func test_line_zeroWords_pluralises() {
        XCTAssertEqual(NoteMetadata.line(project: "KB", modified: nil, wordCount: 0, now: now, calendar: cal),
                       "KB · 0 words")
    }
}
