import Foundation

/// Pure recurrence logic, mirroring the predecessor app's server/recurrence.ts.
public enum RecurrenceEngine {
    /// The next occurrence strictly after `date`, per `rule`.
    public static func nextDate(
        _ rule: Recurrence, after date: Date, calendar: Calendar = .current
    ) -> Date {
        switch rule {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)!
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)!
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: date)!
            while calendar.isDateInWeekend(next) {
                next = calendar.date(byAdding: .day, value: 1, to: next)!
            }
            return next
        case .monthly:
            // Foundation clamps the day to the target month's last valid day.
            return calendar.date(byAdding: .month, value: 1, to: date)!
        }
    }
}
