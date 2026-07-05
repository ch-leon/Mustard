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
}
