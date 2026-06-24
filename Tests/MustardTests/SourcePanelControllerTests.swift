import XCTest
@testable import MustardKit

final class SourcePanelControllerTests: XCTestCase {
    func test_open_setsCurrentAndPresents() {
        let controller = SourcePanelController()
        XCTAssertNil(controller.current)
        XCTAssertFalse(controller.isPresented)

        let link = SourceLink(sourceURL: "https://app.shortcut.com/s/1", source: "shortcut", title: "T")!
        controller.open(link)

        XCTAssertEqual(controller.current, link)
        XCTAssertTrue(controller.isPresented)
    }

    func test_open_replacesCurrent() {
        let controller = SourcePanelController()
        let a = SourceLink(sourceURL: "https://a.com", source: "jira", title: "A")!
        let b = SourceLink(sourceURL: "https://b.com", source: "shortcut", title: "B")!
        controller.open(a)
        controller.open(b)
        XCTAssertEqual(controller.current, b)
        XCTAssertTrue(controller.isPresented)
    }
}
