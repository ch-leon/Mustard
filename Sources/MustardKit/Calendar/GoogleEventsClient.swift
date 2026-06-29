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
        let (data, status) = try await transport(req)
        // Fail loudly on non-2xx. Otherwise a Google error body (no `items`) would parse
        // to [] and the upsert reconciler would delete every synced event — silent data
        // loss. 401 → invalidGrant so the service clears the token; others keep last sync.
        guard (200..<300).contains(status) else {
            throw status == 401 ? GoogleAuthError.invalidGrant : GoogleAuthError.server("events status \(status)")
        }
        return GoogleCalendarParser.parseEvents(data)
    }
}
