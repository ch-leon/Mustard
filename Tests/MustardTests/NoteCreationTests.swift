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
}
