import Foundation

/// Pure selection for the one-time backlog prune (see the 2026-06-24 spec).
/// Meeting tasks were historically imported team-wide; this picks the stale ones
/// — those whose source meeting is more than `days` old — so the runner can mark
/// them done. Deterministic: the meeting date is parsed from the note path in UTC,
/// matching `MeetingTaskParser`'s formatters; `now` is injected (never the clock).
public enum MeetingTaskCleanup {
    /// Meeting-sourced tasks whose note is dated strictly more than `days` before `now`.
    public static func tasksToArchive(
        _ tasks: [MustardTask], now: Date, olderThanDays days: Int = 7
    ) -> [MustardTask] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return tasks.filter { task in
            guard task.source == "meeting",
                  let date = meetingDate(fromPath: task.sourceURL) else { return false }
            return date < cutoff
        }
    }

    /// Parse the ISO date embedded in a meeting note path, e.g.
    /// `DL/meetings/2026/05/2026-05-29-slug.md` → 2026-05-29 (UTC). `nil` if absent.
    static func meetingDate(fromPath path: String?) -> Date? {
        guard let path else { return nil }
        let name = (path as NSString).lastPathComponent
        guard let r = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression)
        else { return nil }
        return isoDay.date(from: String(name[r]))
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
