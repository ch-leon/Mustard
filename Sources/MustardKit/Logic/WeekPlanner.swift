import Foundation

/// Pure week-grid logic for the planner (Mon-start, 7 days).
public enum WeekPlanner {
    /// The 7 dates (Mon→Sun) of the week containing `reference`, shifted by `weekOffset`.
    public static func days(weekOffset: Int, reference: Date = .now, calendar: Calendar = .current) -> [Date] {
        let startOfDay = calendar.startOfDay(for: reference)
        let weekday = calendar.component(.weekday, from: startOfDay) // 1=Sun…7=Sat
        let daysFromMonday = (weekday + 5) % 7 // Mon→0, Sun→6
        guard let monday = calendar.date(
            byAdding: .day, value: -daysFromMonday + weekOffset * 7, to: startOfDay
        ) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    /// Open, unscheduled tasks owned by me — the rail.
    public static func unscheduled(_ tasks: [MustardTask]) -> [MustardTask] {
        tasks.filter { $0.owner == .me && $0.scheduledAt == nil && $0.status.isOpen }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Tasks scheduled on `day`, ordered by time.
    public static func tasks(_ tasks: [MustardTask], on day: Date, calendar: Calendar = .current) -> [MustardTask] {
        tasks
            .filter { task in
                guard let when = task.scheduledAt else { return false }
                return calendar.isDate(when, inSameDayAs: day)
            }
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }
    }

    /// Date for scheduling onto `day`, keeping a task's existing time-of-day (default 9:00).
    public static func scheduleDate(
        on day: Date, keepingTimeFrom existing: Date?, calendar: Calendar = .current
    ) -> Date? {
        var hour = 9, minute = 0
        if let existing {
            hour = calendar.component(.hour, from: existing)
            minute = calendar.component(.minute, from: existing)
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
