import XCTest
@testable import MustardKit

final class RitualPromptTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private let now = Date(timeIntervalSince1970: 1_751_790_000)   // mid-day UTC

    func test_neverPlannedNorDismissed_offers() {
        XCTAssertTrue(RitualPrompt.shouldOffer(lastPlannedDay: nil, dismissedDay: nil, now: now, calendar: cal))
    }
    func test_plannedToday_doesNotOffer() {
        XCTAssertFalse(RitualPrompt.shouldOffer(lastPlannedDay: now.addingTimeInterval(-3_600), dismissedDay: nil, now: now, calendar: cal))
    }
    func test_dismissedToday_doesNotOffer() {
        XCTAssertFalse(RitualPrompt.shouldOffer(lastPlannedDay: nil, dismissedDay: now, now: now, calendar: cal))
    }
    func test_plannedYesterday_offersAgain() {
        XCTAssertTrue(RitualPrompt.shouldOffer(lastPlannedDay: now.addingTimeInterval(-86_400), dismissedDay: now.addingTimeInterval(-86_400), now: now, calendar: cal))
    }
    func test_midnightBoundary_plannedLateYesterday_offersJustAfterMidnight() {
        // 1_751_760_000 is exactly midnight UTC; planning at 23:59 must not
        // suppress the offer at 00:01 — both stamps reset on the day boundary.
        let midnight = Date(timeIntervalSince1970: 1_751_760_000)
        let lateYesterday = midnight.addingTimeInterval(-60)     // 23:59
        let justAfter = midnight.addingTimeInterval(60)          // 00:01
        XCTAssertTrue(RitualPrompt.shouldOffer(lastPlannedDay: lateYesterday, dismissedDay: lateYesterday, now: justAfter, calendar: cal))
        XCTAssertFalse(RitualPrompt.shouldOffer(lastPlannedDay: lateYesterday, dismissedDay: nil, now: midnight.addingTimeInterval(-30), calendar: cal))
    }
}
