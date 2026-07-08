import Foundation

/// Pure recurrence logic, mirroring the predecessor app's server/recurrence.ts.
public enum RecurrenceEngine {
    /// The next occurrence strictly after `date`, per `rule`.
    public static func nextDate(
        _ rule: Recurrence, after date: Date, calendar: Calendar = .current
    ) -> Date {
        switch rule {
        case .daily:
            // `calendar.date(byAdding:...)` is effectively always non-nil for these
            // simple additions; the `??` fallback is a never-hit safety net, not a
            // behavior change.
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date.addingTimeInterval(7 * 86_400)
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
            while calendar.isDateInWeekend(next) {
                next = calendar.date(byAdding: .day, value: 1, to: next) ?? next.addingTimeInterval(86_400)
            }
            return next
        case .monthly:
            // Foundation clamps the day to the target month's last valid day.
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(30 * 86_400)
        }
    }

    /// A fresh, un-inserted next instance of a recurring task, or nil if it doesn't
    /// recur. Carries title/notes/priority/tags/owner/list/parent/recurrence; advances
    /// `dueAt` from `dueAt ?? now`; resets status to .inbox; records `recurredFrom`.
    /// The caller inserts the result into a context (see TaskCompletion).
    public static func nextInstance(
        of task: MustardTask, now: Date = .now, calendar: Calendar = .current
    ) -> MustardTask? {
        guard let rule = task.recurrence else { return nil }
        let anchor = task.dueAt ?? now
        let next = MustardTask(title: task.title)
        next.notes = task.notes
        next.priority = task.priority
        next.tags = task.tags
        next.estimateMinutes = task.estimateMinutes
        next.owner = task.owner
        next.list = task.list
        next.parent = task.parent
        next.recurrence = rule
        next.dueAt = nextDate(rule, after: anchor, calendar: calendar)
        next.stage = .inbox
        next.recurredFrom = task.uid
        return next
    }
}
