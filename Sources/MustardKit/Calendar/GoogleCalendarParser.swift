import Foundation

/// A parsed Google Calendar event (value type; mapped to CalendarEvent on upsert).
public struct ParsedEvent: Equatable {
    public let externalId: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let joinURL: String?
    public let location: String?
}

/// Pure parser for the Google Calendar `events.list` response.
public enum GoogleCalendarParser {
    public static func parseEvents(_ data: Data) -> [ParsedEvent] {
        struct Response: Decodable { let items: [Item]? }
        struct Item: Decodable {
            let id: String?
            let summary: String?
            let status: String?
            let start: Stamp?
            let end: Stamp?
            let hangoutLink: String?
            let location: String?
        }
        struct Stamp: Decodable {
            let dateTime: String?
            let date: String?
        }

        guard let resp = try? JSONDecoder().decode(Response.self, from: data),
              let items = resp.items else { return [] }

        let rfc3339 = ISO8601DateFormatter()
        rfc3339.formatOptions = [.withInternetDateTime]
        let rfc3339Frac = ISO8601DateFormatter()
        rfc3339Frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dayOnly = DateFormatter()
        dayOnly.calendar = Calendar(identifier: .gregorian)
        dayOnly.dateFormat = "yyyy-MM-dd"

        func parseStamp(_ s: Stamp?) -> (date: Date, allDay: Bool)? {
            guard let s else { return nil }
            if let dt = s.dateTime {
                if let d = rfc3339.date(from: dt) ?? rfc3339Frac.date(from: dt) {
                    return (d, false)
                }
            }
            if let day = s.date, let d = dayOnly.date(from: day) {
                return (d, true)
            }
            return nil
        }

        return items.compactMap { item -> ParsedEvent? in
            guard item.status != "cancelled",
                  let id = item.id,
                  let start = parseStamp(item.start),
                  let end = parseStamp(item.end) else { return nil }
            return ParsedEvent(
                externalId: id,
                title: item.summary ?? "(no title)",
                start: start.date,
                end: end.date,
                isAllDay: start.allDay,
                joinURL: item.hangoutLink,
                location: item.location
            )
        }
    }
}
