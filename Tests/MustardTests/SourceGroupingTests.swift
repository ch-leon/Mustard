import XCTest
@testable import MustardKit

final class SourceGroupingTests: XCTestCase {
    private func rec(_ title: String, item: String?) -> Recommendation {
        let r = Recommendation(title: title)
        r.sourceItemID = item
        return r
    }

    func test_sharedSourceItemID_groupsTogether() {
        let groups = SourceGrouping.grouped([
            rec("Reply to Ruby", item: "thread-1"),
            rec("Find answers", item: "thread-1"),
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].isMultiSource)
        XCTAssertEqual(groups[0].members.map(\.title), ["Reply to Ruby", "Find answers"])
    }

    func test_distinctSourceItemID_areSeparateSingletons() {
        let groups = SourceGrouping.grouped([
            rec("A", item: "thread-1"),
            rec("B", item: "thread-2"),
        ])
        XCTAssertEqual(groups.count, 2)
        XCTAssertFalse(groups[0].isMultiSource)
        XCTAssertFalse(groups[1].isMultiSource)
    }

    func test_nilSourceItemID_neverGroups() {
        let groups = SourceGrouping.grouped([rec("A", item: nil), rec("B", item: nil)])
        XCTAssertEqual(groups.count, 2)
    }

    func test_preservesFirstAppearanceOrder() {
        let groups = SourceGrouping.grouped([
            rec("first", item: "t1"),
            rec("second", item: "t2"),
            rec("first-again", item: "t1"),
        ])
        XCTAssertEqual(groups.map(\.id), ["t1", "t2"])
        XCTAssertEqual(groups[0].members.count, 2)
    }
}
