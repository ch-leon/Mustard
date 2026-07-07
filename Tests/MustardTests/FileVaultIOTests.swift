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

    func test_write_createsIntermediateDirectories() throws {
        let io = FileVaultIO(rootPath: dir)
        try io.write("notes/new/idea.md", "# Idea\n")
        XCTAssertEqual(io.read("notes/new/idea.md"), "# Idea\n")
    }
}
