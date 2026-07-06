import XCTest
@testable import MustardKit

final class SlashMenuTests: XCTestCase {

    // MARK: - Items + filter

    func test_items_unfiltered_fiveCommands_orderPinned() {
        XCTAssertEqual(SlashMenu.items(query: "").map(\.id),
                       ["todo", "heading", "link", "subpage", "agent"])
    }
    func test_items_filter_caseInsensitive_titleContains() {
        // Word-prefix matching, not substring-contains: "he" must NOT leak
        // "Ask *the* agent" in via "the".
        XCTAssertEqual(SlashMenu.items(query: "he").map(\.id), ["heading"])
        XCTAssertEqual(SlashMenu.items(query: "AGE"), SlashMenu.items(query: "age"))
    }
    func test_items_filter_matchesAnyTitleWordPrefix() {
        XCTAssertEqual(SlashMenu.items(query: "age").map(\.id), ["agent"])
        XCTAssertEqual(SlashMenu.items(query: "note").map(\.id), ["link"])
        XCTAssertEqual(SlashMenu.items(query: "sub").map(\.id), ["subpage"])
    }
    func test_items_noMatch_isEmpty() {
        XCTAssertTrue(SlashMenu.items(query: "zzz").isEmpty)
    }

    // MARK: - Trigger detection

    func test_activeQuery_onlyAtLineStart_noWhitespace() {
        XCTAssertEqual(SlashMenu.activeQuery(linePrefix: "/"), "")
        XCTAssertEqual(SlashMenu.activeQuery(linePrefix: "/hea"), "hea")
        XCTAssertNil(SlashMenu.activeQuery(linePrefix: "a /hea"))
        XCTAssertNil(SlashMenu.activeQuery(linePrefix: "/he a"))
        XCTAssertNil(SlashMenu.activeQuery(linePrefix: ""))
    }
    func test_activeQuery_leadingWhitespace_isNotATrigger() {
        // The line up to the caret must be EXACTLY "/" + query.
        XCTAssertNil(SlashMenu.activeQuery(linePrefix: " /he"))
        XCTAssertNil(SlashMenu.activeQuery(linePrefix: "\t/he"))
    }

    // MARK: - Insertions (byte-exact — the menu's only source-producing output)

    func test_insertion_todo_heading_byteExact() {
        XCTAssertEqual(SlashMenu.insertion(for: .todo, noteTitle: nil).text, "- [ ] ")
        XCTAssertEqual(SlashMenu.insertion(for: .heading, noteTitle: nil).text, "## ")
    }
    func test_insertion_todo_heading_caretAtEnd() {
        XCTAssertEqual(SlashMenu.insertion(for: .todo, noteTitle: nil).caretOffset, 6)
        XCTAssertEqual(SlashMenu.insertion(for: .heading, noteTitle: nil).caretOffset, 3)
    }
    func test_insertion_linkToNote_caretInsideBrackets() {
        let ins = SlashMenu.insertion(for: .linkToNote, noteTitle: nil)
        XCTAssertEqual(ins.text, "[[]]"); XCTAssertEqual(ins.caretOffset, 2)
    }
    func test_insertion_linkToNote_withTitle_interpolates_caretAtEnd() {
        let ins = SlashMenu.insertion(for: .linkToNote, noteTitle: "Setup")
        XCTAssertEqual(ins.text, "[[Setup]]"); XCTAssertEqual(ins.caretOffset, 9)
    }
    func test_insertion_subpage_interpolatesTitle() {
        XCTAssertEqual(SlashMenu.insertion(for: .subpage, noteTitle: "New page").text, "[[New page]]\n")
    }
    func test_insertion_subpage_caretAfterNewline_utf16() {
        let ins = SlashMenu.insertion(for: .subpage, noteTitle: "New page")
        XCTAssertEqual(ins.caretOffset, ("[[New page]]\n" as NSString).length)
        // Non-BMP title: caret offset counts UTF-16 units, not characters.
        let emoji = SlashMenu.insertion(for: .subpage, noteTitle: "🗒 Plan")
        XCTAssertEqual(emoji.text, "[[🗒 Plan]]\n")
        XCTAssertEqual(emoji.caretOffset, ("[[🗒 Plan]]\n" as NSString).length)
    }
    func test_insertion_subpage_nilOrEmptyTitle_fallsBackUntitled() {
        // Mirrors NoteCreation's empty-title fallback so link and file agree.
        XCTAssertEqual(SlashMenu.insertion(for: .subpage, noteTitle: nil).text, "[[Untitled]]\n")
        XCTAssertEqual(SlashMenu.insertion(for: .subpage, noteTitle: "").text, "[[Untitled]]\n")
    }
    func test_insertion_askAgent_isVaultReadableCallout() {
        XCTAssertEqual(SlashMenu.insertion(for: .askAgent, noteTitle: nil).text, "> [!agent] ")
    }
}
