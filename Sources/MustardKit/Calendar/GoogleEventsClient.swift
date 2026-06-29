import Foundation

/// HTTP for Google Calendar `events.list`. URL builder is pure; network is injected;
/// parsing reuses `GoogleCalendarParser`.
public struct GoogleEventsClient {
    let transport: HTTPTransport

    public init(transport: @escaping HTTPTransport = GoogleTokenClient.defaultTransport) {
        self.transport = transport
    }

    public static func eventsURL(calendarId: String, window: CalendarWindow) -> URL {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        var c = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarId)/events")!
        c.queryItems = [
            .init(name: "timeMin", value: f.string(from: window.start)),
            .init(name: "timeMax", value: f.string(from: window.end)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "maxResults", value: "250"),
        ]
        return c.url!
    }

    public func fetch(accessToken: String, calendarId: String,
                      window: CalendarWindow) async throws -> [ParsedEvent] {
        var req = URLRequest(url: Self.eventsURL(calendarId: calendarId, window: window))
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data = try await transport(req)
        return GoogleCalendarParser.parseEvents(data)
    }
}
