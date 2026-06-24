import XCTest
@testable import MustardKit

final class SourceLinkTests: XCTestCase {
    // MARK: scheme allow-list
    func test_https_resolves() {
        let link = SourceLink(sourceURL: "https://app.shortcut.com/story/3920", source: "shortcut", title: "Cadence")
        XCTAssertNotNil(link)
        XCTAssertEqual(link?.url.absoluteString, "https://app.shortcut.com/story/3920")
        XCTAssertEqual(link?.label, "Cadence")
        XCTAssertEqual(link?.sourceKind, "shortcut")
    }

    func test_http_resolves() {
        XCTAssertNotNil(SourceLink(sourceURL: "http://example.com/x", source: "jira", title: "T"))
    }

    func test_fileScheme_rejected() {
        XCTAssertNil(SourceLink(sourceURL: "file:///etc/passwd", source: "vault", title: "T"))
    }

    func test_javascriptScheme_rejected() {
        XCTAssertNil(SourceLink(sourceURL: "javascript:alert(1)", source: "vault", title: "T"))
    }

    func test_obsidianScheme_rejected() {
        XCTAssertNil(SourceLink(sourceURL: "obsidian://open?vault=x", source: "vault", title: "T"))
    }

    func test_emptyAndNil_rejected() {
        XCTAssertNil(SourceLink(sourceURL: nil, source: "shortcut", title: "T"))
        XCTAssertNil(SourceLink(sourceURL: "", source: "shortcut", title: "T"))
        XCTAssertNil(SourceLink(sourceURL: "   ", source: "shortcut", title: "T"))
    }

    func test_vaultNotePath_rejected() {
        // Meeting tasks store a vault-relative note path here, not a web URL.
        XCTAssertNil(SourceLink(sourceURL: "Codeheroes work/Meetings/2026-06-01.md", source: "meeting", title: "T"))
    }

    // MARK: symbol / name mapping
    func test_symbol_perKind() {
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "shortcut", title: "T")?.symbol, "checklist")
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "jira", title: "T")?.symbol, "ticket")
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "gmail", title: "T")?.symbol, "envelope.fill")
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "vault", title: "T")?.symbol, "books.vertical")
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "carrier-pigeon", title: "T")?.symbol, "link")
    }

    func test_sourceName_perKind() {
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "shortcut", title: "T")?.sourceName, "Shortcut")
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "jira", title: "T")?.sourceName, "Jira")
        XCTAssertEqual(SourceLink(sourceURL: "https://a.co", source: "carrier-pigeon", title: "T")?.sourceName, "Source")
    }

    // MARK: model resolvers
    func test_fromRecommendation() {
        let r = Recommendation(title: "Rec", source: "shortcut", sourceURL: "https://app.shortcut.com/s/1")
        XCTAssertEqual(SourceLink(from: r)?.label, "Rec")
        XCTAssertEqual(SourceLink(from: r)?.sourceKind, "shortcut")
    }

    func test_fromRecommendation_noURL_nil() {
        XCTAssertNil(SourceLink(from: Recommendation(title: "Vault note", source: "vault")))
    }

    func test_fromMustardTask() {
        let t = MustardTask(title: "Task")
        t.source = "jira"
        t.sourceURL = "https://jira.example.com/BROWSE-1"
        XCTAssertEqual(SourceLink(from: t)?.url.absoluteString, "https://jira.example.com/BROWSE-1")
    }

    func test_fromOutputCard_viaParent() {
        let r = Recommendation(title: "Parent", source: "gmail", sourceURL: "https://mail.example.com/t/1")
        let card = OutputCard(content: "done", kind: "summary", recommendation: r)
        XCTAssertEqual(SourceLink(from: card)?.url.absoluteString, "https://mail.example.com/t/1")
        XCTAssertEqual(SourceLink(from: card)?.label, "Parent")
    }

    func test_fromOutputCard_noParent_nil() {
        XCTAssertNil(SourceLink(from: OutputCard(content: "x", kind: "summary")))
    }
}
