import XCTest
@testable import MustardKit

final class BoardSettingsTests: XCTestCase {
    func test_defaults() {
        let s = BoardSettings(store: UserDefaults(suiteName: "test.board.\(UUID().uuidString)")!)
        XCTAssertEqual(s.defaultView, .everyone)
        XCTAssertFalse(s.compact)
        XCTAssertTrue(s.showConfidence)
    }

    func test_roundTrips() {
        let store = UserDefaults(suiteName: "test.board.\(UUID().uuidString)")!
        var s = BoardSettings(store: store)
        s.defaultView = .agent
        s.compact = true
        s.showConfidence = false
        let s2 = BoardSettings(store: store)
        XCTAssertEqual(s2.defaultView, .agent)
        XCTAssertTrue(s2.compact)
        XCTAssertFalse(s2.showConfidence)
    }
}
