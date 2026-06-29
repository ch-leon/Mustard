import Foundation
import SwiftData

/// Reconcile fetched events into `CalendarEvent` rows for one calendar + window:
/// update matches by `externalId`, insert new, delete in-window rows that vanished.
public func upsertEvents(_ parsed: [ParsedEvent], into context: ModelContext,
                         calendarId: String, window: CalendarWindow) throws {
    let lo = window.start, hi = window.end
    let descriptor = FetchDescriptor<CalendarEvent>(
        predicate: #Predicate { $0.calendarId == calendarId && $0.start >= lo && $0.start < hi })
    let existing = try context.fetch(descriptor)
    let byId = Dictionary(existing.map { ($0.externalId, $0) }, uniquingKeysWith: { a, _ in a })
    let incomingIds = Set(parsed.map(\.externalId))

    for p in parsed {
        if let e = byId[p.externalId] {
            e.title = p.title; e.start = p.start; e.end = p.end
            e.isAllDay = p.isAllDay; e.joinURL = p.joinURL; e.location = p.location
            e.updatedAt = .now
        } else {
            context.insert(CalendarEvent(
                externalId: p.externalId, calendarId: calendarId, title: p.title,
                start: p.start, end: p.end, isAllDay: p.isAllDay,
                joinURL: p.joinURL, location: p.location))
        }
    }
    for e in existing where !incomingIds.contains(e.externalId) { context.delete(e) }
    try context.save()
}
