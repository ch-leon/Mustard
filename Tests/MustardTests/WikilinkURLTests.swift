import XCTest
@testable import MustardKit

final class WikilinkURLTests: XCTestCase {
    func test_urlRoundTrip_spacesSlashesUnicode() {
        for target in ["My Note", "guides/Deep Dive", "café — 日本語", "100% done", "Q1 Plans + Goals"] {
            let url = WikilinkURL.url(for: target)
            XCTAssertNotNil(url, "no URL for \(target)")
            XCTAssertEqual(url.flatMap(WikilinkURL.target(from:)), target)
        }
    }
    func test_target_rejectsForeignSchemes() {
        XCTAssertNil(WikilinkURL.target(from: URL(string: "https://example.com/?t=x")!))
        XCTAssertNil(WikilinkURL.target(from: URL(string: "obsidian://open?t=x")!))
    }
    func test_target_missingQueryItem_isNil() {
        XCTAssertNil(WikilinkURL.target(from: URL(string: "mustard-note://link")!))
    }
    func test_url_usesMustardNoteScheme() {
        XCTAssertEqual(WikilinkURL.url(for: "X")?.scheme, "mustard-note")
    }
}
