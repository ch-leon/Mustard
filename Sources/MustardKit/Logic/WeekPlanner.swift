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
        tasks.filter { $0.owner == .me && $0.scheduledAt == nil && $0.stage.isOpen }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Open, my tasks scheduled before today — the OVERDUE rail. These are pulled
    /// off their past day so they can be re-planned. Oldest first.
    public static func overdue(_ tasks: [MustardTask], now: Date = .now, calendar: Calendar = .current) -> [MustardTask] {
        let todayStart = calendar.startOfDay(for: now)
        return tasks
            .filter { task in
                guard task.owner == .me, task.stage.isOpen, let when = task.scheduledAt else { return false }
                return when < todayStart
            }
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }
    }

    /// Tasks scheduled on `day`, ordered by time. Overdue open *my* tasks are
    /// excluded — they live in the rail (see `overdue`) — but done and agent
    /// tasks still render on their day.
    public static func tasks(
        _ tasks: [MustardTask], on day: Date, now: Date = .now, calendar: Calendar = .current
    ) -> [MustardTask] {
        let overdueIds = Set(overdue(tasks, now: now, calendar: calendar).map(\.uid))
        return tasks
            .filter { task in
                guard let when = task.scheduledAt else { return false }
                guard calendar.isDate(when, inSameDayAs: day) else { return false }
                return !overdueIds.contains(task.uid)
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

    /// Snap a dragged duration to the 30-min grid, with a floor (resize handle).
    public static func snapDuration(_ minutes: Int, snap: Int = 30, min floor: Int = 30) -> Int {
        let snapped = Int((Double(minutes) / Double(snap)).rounded()) * snap
        return Swift.max(floor, snapped)
    }

    // MARK: - Axis overlap layout

    /// A timed item on the day axis, abstracted from event/task (minute spans)
    /// so the overlap layout stays pure and unit-testable.
    public struct AxisSpan: Equatable {
        public let id: String
        public let startMinute: Int
        public let endMinute: Int
        public init(id: String, startMinute: Int, endMinute: Int) {
            self.id = id
            self.startMinute = startMinute
            self.endMinute = endMinute
        }
    }

    /// Side-by-side placement for an axis item: its column and the number of
    /// columns in its overlap cluster (so the view can size width = 1/count).
    public struct AxisPlacement: Equatable {
        public let column: Int
        public let columnCount: Int
        public init(column: Int, columnCount: Int) {
            self.column = column
            self.columnCount = columnCount
        }
    }

    /// Assign overlapping axis items to side-by-side columns (calendar-style) so
    /// concurrent meetings/tasks stop drawing on top of each other. Greedy
    /// first-fit within each connected overlap cluster; column count resets
    /// between clusters. Returns placements keyed by span id.
    public static func axisColumns(_ spans: [AxisSpan]) -> [String: AxisPlacement] {
        let sorted = spans.sorted {
            $0.startMinute != $1.startMinute ? $0.startMinute < $1.startMinute : $0.endMinute < $1.endMinute
        }
        var result: [String: AxisPlacement] = [:]
        var clusterIDs: [String] = []
        var columnEnds: [Int] = []   // end minute of the last span placed in each column
        var clusterMaxEnd = Int.min

        func flushCluster() {
            let count = columnEnds.count
            for id in clusterIDs {
                if let p = result[id] {
                    result[id] = AxisPlacement(column: p.column, columnCount: count)
                }
            }
            clusterIDs.removeAll()
            columnEnds.removeAll()
            clusterMaxEnd = Int.min
        }

        for span in sorted {
            let end = max(span.endMinute, span.startMinute + 1) // zero-length still occupies a slot
            // New cluster once this span starts at/after everything seen so far.
            if !clusterIDs.isEmpty && span.startMinute >= clusterMaxEnd {
                flushCluster()
            }
            // First column whose last item has ended by this span's start.
            var placedColumn: Int?
            for col in columnEnds.indices where columnEnds[col] <= span.startMinute {
                columnEnds[col] = end
                placedColumn = col
                break
            }
            let column = placedColumn ?? {
                columnEnds.append(end)
                return columnEnds.count - 1
            }()
            result[span.id] = AxisPlacement(column: column, columnCount: 0) // count fixed on flush
            clusterIDs.append(span.id)
            clusterMaxEnd = Swift.max(clusterMaxEnd, end)
        }
        flushCluster()
        return result
    }

    /// Minutes between the axis start (`dayStartHour`) and `date`'s time-of-day.
    /// Negative when `date` is before the visible window. The view multiplies by
    /// points-per-minute to place a timed block.
    public static func minutesSinceDayStart(
        _ date: Date, dayStartHour: Int, calendar: Calendar = .current
    ) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return ((c.hour ?? 0) - dayStartHour) * 60 + (c.minute ?? 0)
    }
}
