import XCTest
import SwiftData
@testable import MustardKit

final class CalendarSyncTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CalendarEvent.self, configurations: config)
        return ModelContext(container)
    }
    private func parsed(_ id: String, _ title: String, start: Date) -> ParsedEvent {
        ParsedEvent(externalId: id, title: title, start: start, end: start.addingTimeInterval(900),
                    isAllDay: false, joinURL: nil, location: nil)
    }

    func testInsertsNewEvents() throws {
        let ctx = try makeContext()
        let win = CalendarWindow(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100_000))
        try upsertEvents([parsed("e1", "A", start: Date(timeIntervalSince1970: 10))],
                         into: ctx, calendarId: "primary", window: win)
        let all = try ctx.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(all.map(\.externalId), ["e1"])
    }

    func testUpdatesExistingByExternalId() throws {
        let ctx = try makeContext()
        let win = CalendarWindow(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100_000))
        let t = Date(timeIntervalSince1970: 10)
        try upsertEvents([parsed("e1", "Old", start: t)], into: ctx, calendarId: "primary", window: win)
        try upsertEvents([parsed("e1", "New", start: t)], into: ctx, calendarId: "primary", window: win)
        let all = try ctx.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "New")
    }

    func testDeletesVanishedInWindow() throws {
        let ctx = try makeContext()
        let win = CalendarWindow(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100_000))
        let t = Date(timeIntervalSince1970: 10)
        try upsertEvents([parsed("e1", "A", start: t), parsed("e2", "B", start: t)],
                         into: ctx, calendarId: "primary", window: win)
        try upsertEvents([parsed("e1", "A", start: t)], into: ctx, calendarId: "primary", window: win)
        let all = try ctx.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(all.map(\.externalId), ["e1"])
    }
}
