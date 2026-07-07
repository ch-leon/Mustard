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

    // Additional coverage: filename match (not title) + case-insensitive sort of folders.
    func test_filter_matchesFilename_whenTitleDiffers() {
        let root = NoteTree.build([("archive/adv-notes.md", "Completely Different Title")])
        let filtered = NoteTree.filter(root, query: "adv-notes")
        XCTAssertEqual(filtered.subfolders.map(\.name), ["archive"])
        XCTAssertEqual(filtered.subfolders[0].notes.map(\.relativePath), ["archive/adv-notes.md"])
    }
    func test_build_sortsFoldersCaseInsensitively() {
        let root = NoteTree.build([("Zeta/a.md", "A"), ("alpha/b.md", "B")])
        XCTAssertEqual(root.subfolders.map(\.name), ["alpha", "Zeta"])
    }
    func test_isActiveQuery_trueOnlyWhenTrimmedNonEmpty() {
        XCTAssertTrue(NoteTree.isActiveQuery("setup"))
        XCTAssertTrue(NoteTree.isActiveQuery(" x "))
        XCTAssertFalse(NoteTree.isActiveQuery(""))
        XCTAssertFalse(NoteTree.isActiveQuery("  \n"))
    }
    func test_filter_noMatch_prunesEverything() {
        let root = NoteTree.build(notes)
        let filtered = NoteTree.filter(root, query: "zzznomatch")
        XCTAssertTrue(filtered.notes.isEmpty)
        XCTAssertTrue(filtered.subfolders.isEmpty)
    }
}
