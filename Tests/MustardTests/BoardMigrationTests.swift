import XCTest
@testable import MustardKit

final class BoardMigrationTests: XCTestCase {
    func test_meTask_mapsByStatus() {
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .inbox, scheduledAt: nil, owner: .me), .inbox)
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .inProgress, scheduledAt: nil, owner: .me), .inProgress)
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .done, scheduledAt: nil, owner: .me), .done)
    }

    func test_someday_collapsesToInbox() {
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .someday, scheduledAt: nil, owner: .me), .inbox)
    }

    func test_plannedWithDate_becomesScheduled() {
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .planned, scheduledAt: Date(timeIntervalSince1970: 1), owner: .me), .scheduled)
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .planned, scheduledAt: nil, owner: .me), .planned)
    }

    func test_agentTask_landsInQueued() {
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .inProgress, scheduledAt: nil, owner: .agent), .queued)
        XCTAssertEqual(BoardMigration.stage(legacyStatus: .done, scheduledAt: nil, owner: .agent), .done)
    }
}
