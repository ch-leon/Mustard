import XCTest
@testable import MustardKit

final class GoogleCalendarParserTests: XCTestCase {
    func test_parsesTimedEvent_withJoinLink() {
        let json = """
        {"items":[
          {"id":"e1","summary":"Standup","hangoutLink":"https://meet.google.com/x",
           "start":{"dateTime":"2026-06-12T09:30:00+10:00"},
           "end":{"dateTime":"2026-06-12T09:45:00+10:00"}}
        ]}
        """.data(using: .utf8)!
        let events = GoogleCalendarParser.parseEvents(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].externalId, "e1")
        XCTAssertEqual(events[0].title, "Standup")
        XCTAssertFalse(events[0].isAllDay)
        XCTAssertEqual(events[0].joinURL, "https://meet.google.com/x")
    }

    func test_parsesAllDayEvent() {
        let json = """
        {"items":[{"id":"e2","summary":"Leave","start":{"date":"2026-06-12"},"end":{"date":"2026-06-13"}}]}
        """.data(using: .utf8)!
        let events = GoogleCalendarParser.parseEvents(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].isAllDay)
    }

    func test_skipsCancelledAndMissingFields() {
        let json = """
        {"items":[
          {"id":"c1","status":"cancelled","start":{"dateTime":"2026-06-12T09:00:00Z"},"end":{"dateTime":"2026-06-12T10:00:00Z"}},
          {"summary":"no id","start":{"dateTime":"2026-06-12T09:00:00Z"},"end":{"dateTime":"2026-06-12T10:00:00Z"}}
        ]}
        """.data(using: .utf8)!
        XCTAssertEqual(GoogleCalendarParser.parseEvents(json).count, 0)
    }

    func test_missingTitleFallsBack() {
        let json = """
        {"items":[{"id":"e3","start":{"dateTime":"2026-06-12T09:00:00Z"},"end":{"dateTime":"2026-06-12T10:00:00Z"}}]}
        """.data(using: .utf8)!
        XCTAssertEqual(GoogleCalendarParser.parseEvents(json).first?.title, "(no title)")
    }

    func test_emptyOrGarbage() {
        XCTAssertEqual(GoogleCalendarParser.parseEvents(Data("{}".utf8)).count, 0)
        XCTAssertEqual(GoogleCalendarParser.parseEvents(Data("garbage".utf8)).count, 0)
    }
}
