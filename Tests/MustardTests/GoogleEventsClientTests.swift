import XCTest
@testable import MustardKit

final class GoogleEventsClientTests: XCTestCase {
    func testEventsURLHasWindowAndOrdering() {
        let win = CalendarWindow(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86_400))
        let url = GoogleEventsClient.eventsURL(calendarId: "primary", window: win).absoluteString
        XCTAssertTrue(url.contains("/calendars/primary/events"))
        XCTAssertTrue(url.contains("singleEvents=true"))
        XCTAssertTrue(url.contains("orderBy=startTime"))
        XCTAssertTrue(url.contains("timeMin="))
        XCTAssertTrue(url.contains("timeMax="))
    }

    func testFetchParsesEvents() async throws {
        let json = #"{"items":[{"id":"e1","summary":"Standup","status":"confirmed","start":{"dateTime":"2026-06-28T09:00:00Z"},"end":{"dateTime":"2026-06-28T09:15:00Z"}}]}"#
        let client = GoogleEventsClient(transport: { _ in (Data(json.utf8), 200) })
        let events = try await client.fetch(
            accessToken: "AT", calendarId: "primary",
            window: CalendarWindow(start: .now, end: .now))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.externalId, "e1")
        XCTAssertEqual(events.first?.title, "Standup")
    }

    // Regression guard: a non-2xx error body must THROW, not parse to [] (which would
    // make the upsert reconciler delete every synced event — silent data loss).
    func testUnauthorizedThrowsInvalidGrant() async {
        let body = #"{"error":{"code":401,"message":"Invalid Credentials"}}"#
        let client = GoogleEventsClient(transport: { _ in (Data(body.utf8), 401) })
        do {
            _ = try await client.fetch(accessToken: "AT", calendarId: "primary",
                                       window: CalendarWindow(start: .now, end: .now))
            XCTFail("expected throw")
        } catch { XCTAssertEqual(error as? GoogleAuthError, .invalidGrant) }
    }

    func testServerErrorThrows() async {
        let client = GoogleEventsClient(transport: { _ in (Data("oops".utf8), 503) })
        do {
            _ = try await client.fetch(accessToken: "AT", calendarId: "primary",
                                       window: CalendarWindow(start: .now, end: .now))
            XCTFail("expected throw")
        } catch { XCTAssertEqual(error as? GoogleAuthError, .server("events status 503")) }
    }
}
