import XCTest
@testable import MustardKit

final class AreaMappingTests: XCTestCase {
    func test_codeForm() {
        XCTAssertEqual(AreaMapping.areaName(forProject: "DL"), "Digital Licence")
        XCTAssertEqual(AreaMapping.areaName(forProject: "Code Heroes"), "Code Heroes")
    }

    func test_folderNameForm() {
        // The real config stores the KB folder name, not the code.
        XCTAssertEqual(AreaMapping.areaName(forProject: "DL-Knowledge-Base"), "Digital Licence")
        XCTAssertEqual(AreaMapping.areaName(forProject: "SB-Knowledge-Base"), "Sales Buddi")
        XCTAssertEqual(AreaMapping.areaName(forProject: "Sandvik-Knowledge-Base"), "Sandvik")
    }

    func test_unknownProject_isNil() {
        XCTAssertNil(AreaMapping.areaName(forProject: "Nope"))
        XCTAssertNil(AreaMapping.areaName(forProject: ""))
    }
}
