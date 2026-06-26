import XCTest
@testable import MustardKit

final class RecommendationSelectionTests: XCTestCase {
    // nextSelection
    func test_nextSelection_keepsCurrentWhenStillPending() {
        let a = Recommendation(title: "A"); let b = Recommendation(title: "B")
        XCTAssertTrue(RecommendationSelection.nextSelection(current: a, pending: [a, b]) === a)
    }
    func test_nextSelection_fallsBackToFirstWhenCurrentGone() {
        let a = Recommendation(title: "A"); let b = Recommendation(title: "B")
        XCTAssertTrue(RecommendationSelection.nextSelection(current: a, pending: [b]) === b)
    }
    func test_nextSelection_firstOnArrival() {
        let a = Recommendation(title: "A"); let b = Recommendation(title: "B")
        XCTAssertTrue(RecommendationSelection.nextSelection(current: nil, pending: [a, b]) === a)
    }
    func test_nextSelection_nilWhenEmpty() {
        XCTAssertNil(RecommendationSelection.nextSelection(current: nil, pending: []))
    }
    // shouldAutoOpenSource
    func test_shouldAutoOpenSource_onWithSource() {
        let r = Recommendation(title: "T", source: "shortcut", sourceURL: "https://app.shortcut.com/s/1")
        XCTAssertTrue(RecommendationSelection.shouldAutoOpenSource(settingOn: true, rec: r))
    }
    func test_shouldAutoOpenSource_onWithoutSource() {
        let r = Recommendation(title: "Vault note", source: "vault")
        XCTAssertFalse(RecommendationSelection.shouldAutoOpenSource(settingOn: true, rec: r))
    }
    func test_shouldAutoOpenSource_offWithSource() {
        let r = Recommendation(title: "T", source: "jira", sourceURL: "https://jira.example.com/1")
        XCTAssertFalse(RecommendationSelection.shouldAutoOpenSource(settingOn: false, rec: r))
    }
    func test_shouldAutoOpenSource_nilRec() {
        XCTAssertFalse(RecommendationSelection.shouldAutoOpenSource(settingOn: true, rec: nil))
    }
}
