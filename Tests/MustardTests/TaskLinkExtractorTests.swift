import XCTest
@testable import MustardKit

/// BAK-91: a create_task rec that references a Shortcut story / Jira issue should
/// land the referenced link on the task. The extractor pulls http(s) URLs from the
/// rec's text fields, labels them by service, and dedupes.
final class TaskLinkExtractorTests: XCTestCase {
    func test_extractsShortcutURL_labelledShortcut() {
        let links = TaskLinkExtractor.referencedLinks(in: [
            "Follow up on https://app.shortcut.com/codeheroes/story/12345 before Friday"
        ])
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.label, "Shortcut")
        XCTAssertEqual(links.first?.url, "https://app.shortcut.com/codeheroes/story/12345")
    }

    func test_extractsJiraURL_labelledJira() {
        let links = TaskLinkExtractor.referencedLinks(in: [
            "ref https://codeheroes.atlassian.net/browse/DIGIDMOB-42"
        ])
        XCTAssertEqual(links.first?.label, "Jira")
    }

    func test_dedupesSameURLAcrossTexts() {
        let u = "https://app.shortcut.com/codeheroes/story/7"
        let links = TaskLinkExtractor.referencedLinks(in: [u, "see \(u) again", nil])
        XCTAssertEqual(links.count, 1)
    }

    func test_multipleDistinctLinks_firstOccurrenceOrder() {
        let links = TaskLinkExtractor.referencedLinks(in: [
            "draft mentions https://app.shortcut.com/x/story/1",
            "and https://codeheroes.atlassian.net/browse/AB-2"
        ])
        XCTAssertEqual(links.map(\.label), ["Shortcut", "Jira"])
    }

    func test_ignoresNonHTTPAndEmpty() {
        let links = TaskLinkExtractor.referencedLinks(in: [
            "mailto:leon@codeheroes.com.au", "no links here", "", nil
        ])
        XCTAssertTrue(links.isEmpty)
    }

    func test_genericURL_labelledByHost() {
        let links = TaskLinkExtractor.referencedLinks(in: ["docs at https://example.com/page"])
        XCTAssertEqual(links.first?.label, "example.com")
    }

    // Review follow-up: label on host boundaries, not substrings, so look-alikes
    // don't get mislabelled as Shortcut/Jira.
    func test_lookalikeHosts_notMislabelled() {
        let links = TaskLinkExtractor.referencedLinks(in: [
            "https://notshortcut.com.evil.example/x",
            "https://mycompany.jira.example.com/y"
        ])
        XCTAssertEqual(links.map(\.label), ["notshortcut.com.evil.example", "mycompany.jira.example.com"])
    }

    // Self-hosted Jira at jira.<company>.com (first host label "jira") still labels Jira.
    func test_selfHostedJira_labelledJira() {
        let links = TaskLinkExtractor.referencedLinks(in: ["https://jira.codeheroes.com/browse/AB-1"])
        XCTAssertEqual(links.first?.label, "Jira")
    }
}
