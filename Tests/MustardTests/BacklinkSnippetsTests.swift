import XCTest
@testable import MustardKit

final class BacklinkSnippetsTests: XCTestCase {
    func test_snippet_firstLineWhoseWikilinkResolvesToTarget() {
        let content = "intro\nsee [[Setup]] here\nlater [[Other]]"
        let s = BacklinkSnippets.snippet(
            in: content, targetPath: "guides/Setup.md", candidatePaths: ["guides/Setup.md", "Other.md"])
        XCTAssertEqual(s, "see [[Setup]] here")
    }
    func test_snippet_aliasAndPathQualifiedLinksStillMatch() {
        XCTAssertEqual(BacklinkSnippets.snippet(
            in: "x [[guides/Setup|the guide]] y", targetPath: "guides/Setup.md",
            candidatePaths: ["guides/Setup.md"]), "x [[guides/Setup|the guide]] y")
    }
    func test_snippet_noMatch_returnsNil() {
        XCTAssertNil(BacklinkSnippets.snippet(in: "no links", targetPath: "A.md", candidatePaths: ["A.md"]))
    }

    // MARK: - Added coverage

    func test_snippet_stripsFrontmatterBeforeScanning() {
        let content = "---\ntitle: Doc\n---\nbody [[Setup]] line"
        XCTAssertEqual(BacklinkSnippets.snippet(
            in: content, targetPath: "Setup.md", candidatePaths: ["Setup.md"]), "body [[Setup]] line")
    }
    func test_snippet_skipsFencedCodeBlocks() {
        let content = "```\ncode [[Setup]] fenced\n```\nreal [[Setup]] line"
        XCTAssertEqual(BacklinkSnippets.snippet(
            in: content, targetPath: "Setup.md", candidatePaths: ["Setup.md"]), "real [[Setup]] line")
    }
    func test_snippet_trimsWhitespace() {
        XCTAssertEqual(BacklinkSnippets.snippet(
            in: "   [[Setup]]   ", targetPath: "Setup.md", candidatePaths: ["Setup.md"]), "[[Setup]]")
    }
    func test_snippet_ignoresLinksResolvingElsewhere() {
        let content = "one [[Other]]\ntwo [[Setup]]"
        XCTAssertEqual(BacklinkSnippets.snippet(
            in: content, targetPath: "Setup.md", candidatePaths: ["Setup.md", "Other.md"]), "two [[Setup]]")
    }
}
