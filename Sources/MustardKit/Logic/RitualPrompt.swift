import Foundation

/// One rule for every morning-ritual entry point (Today banner, notch idle line,
/// ⌘K visibility): offer until the day is planned or the offer is dismissed —
/// both reset at midnight. Pure; state lives in UserDefaults at the call sites.
public enum RitualPrompt {
    public static let lastPlannedKey = "ritualLastPlannedDay"
    public static let dismissedKey = "ritualDismissedDay"
    /// Cross-view trigger: the command bar can't reach Today's local sheet state,
    /// so ⌘K "Plan my day" raises this flag and TodayView consumes + resets it.
    public static let openRequestedKey = "ritualOpenRequested"

    public static func shouldOffer(
        lastPlannedDay: Date?, dismissedDay: Date?, now: Date, calendar: Calendar = .current
    ) -> Bool {
        let isToday: (Date?) -> Bool = { d in d.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
        return !isToday(lastPlannedDay) && !isToday(dismissedDay)
    }
}
