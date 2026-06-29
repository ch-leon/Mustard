import Foundation

/// Pure day-planning logic: no SwiftData queries, no views.
/// Operates on in-memory tasks so it stays trivially unit-testable.
public enum DayPlanner {
    /// Tasks scheduled on `day`, ordered by time.
    public static func tasksForDay(
        _ tasks: [MustardTask], day: Date, calendar: Calendar = .current
    ) -> [MustardTask] {
        tasks
            .filter { task in
                guard let when = task.scheduledAt else { return false }
                return calendar.isDate(when, inSameDayAs: day)
            }
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }
    }

    /// Open tasks with no scheduled date — the inbox rail.
    public static func unscheduled(_ tasks: [MustardTask]) -> [MustardTask] {
        tasks.filter { $0.scheduledAt == nil && $0.stage.isOpen }
    }

    /// Next open, scheduled tasks starting after `after`, soonest first (for the hover panel).
    public static func upcoming(
        _ tasks: [MustardTask], after: Date, limit: Int = 3
    ) -> [MustardTask] {
        tasks
            .filter { task in
                guard task.stage.isOpen, !task.isBlocked, let when = task.scheduledAt else { return false }
                return when > after
            }
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    /// Move open tasks scheduled before `today` onto `today`, keeping their time-of-day.
    public static func carryForward(
        _ tasks: [MustardTask], to today: Date, calendar: Calendar = .current
    ) {
        let startOfToday = calendar.startOfDay(for: today)
        for task in tasks {
            guard task.stage.isOpen, let when = task.scheduledAt,
                  when < startOfToday else { continue }
            let time = calendar.dateComponents([.hour, .minute], from: when)
            task.scheduledAt = calendar.date(
                bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0,
                of: startOfToday
            )
        }
    }
}
