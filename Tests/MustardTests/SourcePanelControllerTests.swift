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
}
