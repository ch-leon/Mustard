import Foundation

public enum GoogleAuthError: Error, Equatable {
    case denied
    case missingCode
    case portBindFailed
    case timeout
    case invalidGrant
    case server(String)
    case network(String)
}

public struct GoogleCredentials: Codable, Equatable {
    public let clientId: String
    public let clientSecret: String
    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
}

public struct CalendarWindow: Equatable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }

    /// Start-of-today through `days` later, in the given calendar.
    public static func rolling(from now: Date, days: Int, calendar: Calendar = .current) -> CalendarWindow {
        let startOfDay = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: days, to: startOfDay)!
        return CalendarWindow(start: startOfDay, end: end)
    }
}

/// Injectable HTTP seam: returns the response body **and** the HTTP status code, so
/// callers can fail loudly on non-2xx instead of mistaking an error body for empty data.
public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, Int)
