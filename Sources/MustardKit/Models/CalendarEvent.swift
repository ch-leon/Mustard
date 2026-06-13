import Foundation
import SwiftData

@Model
public final class CalendarEvent {
    /// Google event id; unique per calendar. Used for upsert (no .unique for CloudKit).
    public var externalId: String = ""
    public var calendarId: String = "primary"
    public var title: String = ""
    public var start: Date = Date.now
    public var end: Date = Date.now
    public var isAllDay: Bool = false
    public var joinURL: String?
    public var location: String?
    public var updatedAt: Date = Date.now

    public init(
        externalId: String = "",
        calendarId: String = "primary",
        title: String = "",
        start: Date = .now,
        end: Date = .now,
        isAllDay: Bool = false,
        joinURL: String? = nil,
        location: String? = nil
    ) {
        self.externalId = externalId
        self.calendarId = calendarId
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.joinURL = joinURL
        self.location = location
        self.updatedAt = .now
    }
}
