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

    // MARK: Capacity + load (BAK-105)

    public enum LoadTier { case green, amber, red }

    public enum TimeOfDay: String, CaseIterable {
        case morning, afternoon, evening, anytime
        public var label: String {
            switch self {
            case .morning: "Morning"
            case .afternoon: "Afternoon"
            case .evening: "Evening"
            case .anytime: "Anytime"
            }
        }
    }

    /// Summed estimate minutes of non-done tasks scheduled on `day`. Clock-independent
    /// (same-day filter, no overdue coupling) so it stays stable for the header bar.
    public static func capacityMinutes(
        _ all: [MustardTask], on day: Date, calendar: Calendar = .current
    ) -> Int {
        all.filter { t in
            guard let when = t.scheduledAt, calendar.isDate(when, inSameDayAs: day) else { return false }
            return t.stage != .done
        }.reduce(0) { $0 + $1.estimateMinutes }
    }

    /// Load tier from minutes: green ≤ 6h, amber > 6h, red (overloaded) > 8h.
    public static func loadTier(minutes: Int) -> LoadTier {
        if minutes > 480 { return .red }
        if minutes > 360 { return .amber }
        return .green
    }

    /// "—" for empty, "45m" under an hour, else hours ("1h", "1.5h", "3.5h").
    public static func capacityLabel(minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = Double(minutes) / 60.0
        let s = hours.rounded() == hours ? String(format: "%.0f", hours) : String(format: "%.1f", hours)
        return "\(s)h"
    }

    /// Time-of-day bucket for a timestamp: Morning < 12:00, Afternoon < 17:00, else Evening.
    public static func timeOfDay(for date: Date, calendar: Calendar = .current) -> TimeOfDay {
        let h = calendar.component(.hour, from: date)
        if h < 12 { return .morning }
        if h < 17 { return .afternoon }
        return .evening
    }

    /// Group tasks into Morning/Afternoon/Evening/Anytime (untimed → Anytime),
    /// preserving that order and omitting empty buckets.
    public static func groupByTimeOfDay(
        _ tasks: [MustardTask], calendar: Calendar = .current
    ) -> [(TimeOfDay, [MustardTask])] {
        var buckets: [TimeOfDay: [MustardTask]] = [:]
        for t in tasks {
            let key: TimeOfDay
            if t.isTimed, let when = t.scheduledAt {
                key = timeOfDay(for: when, calendar: calendar)
            } else {
                key = .anytime
            }
            buckets[key, default: []].append(t)
        }
        return TimeOfDay.allCases.compactMap { tod in
            guard let items = buckets[tod], !items.isEmpty else { return nil }
            return (tod, items)
        }
    }

    // MARK: ✦ Balance (BAK-109)

    public struct BalanceMove: Equatable {
        public let uid: String
        public let from: Date?
        public let to: Date
    }

    public struct BalancePlan: Equatable {
        public let moves: [BalanceMove]
        public let peakMinutes: Int
    }

    /// Redistribute movable (non-done) tasks scheduled within `weekdays` across those
    /// days to flatten the peak load (greedy LPT: largest estimate first into the
    /// least-loaded day; ties prefer the task's current day to minimise churn). Returns
    /// only the tasks that change day, each carrying its prior `scheduledAt` for an exact
    /// Undo. Pure — the caller applies the moves and keeps the snapshot. Meetings
    /// (calendar events) and done tasks are never moved.
    public static func balance(
        _ all: [MustardTask], weekdays: [Date], calendar: Calendar = .current
    ) -> BalancePlan {
        func dayIndex(_ d: Date) -> Int? {
            weekdays.firstIndex { calendar.isDate($0, inSameDayAs: d) }
        }
        let movable = all
            .filter { t in
                guard t.stage != .done, let when = t.scheduledAt else { return false }
                return dayIndex(when) != nil
            }
            .sorted { $0.estimateMinutes > $1.estimateMinutes }

        // Current per-day load, for the no-regression guard below.
        var currentLoads = Array(repeating: 0, count: weekdays.count)
        for t in movable {
            if let i = t.scheduledAt.flatMap(dayIndex) { currentLoads[i] += t.estimateMinutes }
        }
        let currentPeak = currentLoads.max() ?? 0

        var loads = Array(repeating: 0, count: weekdays.count)
        var moves: [BalanceMove] = []
        for t in movable {
            let current = t.scheduledAt.flatMap(dayIndex)
            // Least-loaded bin; on a tie keep the task on its current day.
            var best = 0
            for i in 1..<loads.count where loads[i] < loads[best] { best = i }
            if let current, loads[current] == loads[best] { best = current }
            loads[best] += t.estimateMinutes
            if best != current {
                let to = scheduleDate(on: weekdays[best], keepingTimeFrom: t.scheduledAt) ?? weekdays[best]
                moves.append(BalanceMove(uid: t.uid, from: t.scheduledAt, to: to))
            }
        }
        let newPeak = loads.max() ?? 0
        // No-regression guard: greedy LPT packs from scratch and can occasionally land
        // on a *worse* (or equal) peak than the existing layout. Only commit when we
        // strictly lower the peak — otherwise report "already balanced" (no moves), so
        // Balance never increases load or churns tasks for no gain.
        guard newPeak < currentPeak else {
            return BalancePlan(moves: [], peakMinutes: currentPeak)
        }
        return BalancePlan(moves: moves, peakMinutes: newPeak)
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
