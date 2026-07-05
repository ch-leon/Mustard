import XCTest
@testable import MustardKit

final class WikilinkSyntaxTests: XCTestCase {

    // MARK: - Occurrence scanner

    func test_occurrences_plainHeadingAliasAndEmbedForms() {
        let occs = WikilinkSyntax.occurrences(in: "a [[Note]] b [[Note#H]] c [[Note|alias]] d ![[Img]]")
        XCTAssertEqual(occs.map(\.target), ["Note", "Note", "Note", "Img"])
        XCTAssertEqual(occs.map(\.alias), [nil, nil, "alias", nil])
    }

    func test_occurrences_trimsTargetAndAlias() {
        let occs = WikilinkSyntax.occurrences(in: "[[ Note | the alias ]]")
        XCTAssertEqual(occs.count, 1)
        XCTAssertEqual(occs[0].target, "Note")
        XCTAssertEqual(occs[0].alias, "the alias")
    }

    func test_occurrences_dropsEmptyTargets() {
        XCTAssertTrue(WikilinkSyntax.occurrences(in: "x [[]] y [[ ]] z").isEmpty)
    }

    func test_occurrences_rangeCoversFullMatchIncludingEmbedBang() {
        let line = "see ![[Img]] here"
        let occs = WikilinkSyntax.occurrences(in: line)
        XCTAssertEqual(occs.count, 1)
        XCTAssertEqual((line as NSString).substring(with: occs[0].range), "![[Img]]")
    }

    func test_occurrences_emptyLine_returnsEmpty() {
        XCTAssertTrue(WikilinkSyntax.occurrences(in: "").isEmpty)
    }

    // MARK: - Resolver factory parity with resolve(target:in:)

    func test_resolver_matchesOneShotResolve() {
        let paths = ["guides/Setup.md", "Other.md", "deep/nested/Setup.md"]
        let resolve = WikilinkIndex.resolver(paths: paths)
        for target in ["Setup", "guides/Setup", "Other", "missing", "SETUP", "Other.md"] {
            XCTAssertEqual(resolve(target), WikilinkIndex.resolve(target: target, in: paths),
                           "resolver diverged from resolve() for target '\(target)'")
        }
    }

    func test_resolver_emptyCandidates_returnsNil() {
        XCTAssertNil(WikilinkIndex.resolver(paths: [])("Anything"))
    }

    // MARK: - Snippet overload parity

    func test_snippet_resolverOverload_matchesCandidatePathsOverload() {
        let content = "intro\nsee [[Setup]] here"
        let paths = ["guides/Setup.md", "Other.md"]
        let viaPaths = BacklinkSnippets.snippet(
            in: content, targetPath: "guides/Setup.md", candidatePaths: paths)
        let viaResolver = BacklinkSnippets.snippet(
            in: content, targetPath: "guides/Setup.md",
            resolve: WikilinkIndex.resolver(paths: paths))
        XCTAssertEqual(viaPaths, "see [[Setup]] here")
        XCTAssertEqual(viaResolver, viaPaths)
    }
}
