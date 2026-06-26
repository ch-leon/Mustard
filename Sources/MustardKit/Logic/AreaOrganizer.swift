import Foundation

/// Pure organisation logic for Areas/Lists: filtering and counting tasks by
/// list/area, and stable sort orders. No SwiftData queries, no views — operates
/// on in-memory arrays so it stays trivially unit-testable (mirrors DayPlanner).
public enum AreaOrganizer {
    /// All tasks filed into `list` (any status), oldest first.
    public static func tasks(in list: TaskList, from all: [MustardTask]) -> [MustardTask] {
        all.filter { $0.list === list }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The not-done tasks from an already-scoped list, original order preserved.
    /// (Someday counts as active — it's still open work, just deferred.)
    public static func active(_ tasks: [MustardTask]) -> [MustardTask] {
        tasks.filter { $0.status != .done }
    }

    /// The completed tasks from an already-scoped list, newest completion first.
    public static func completed(_ tasks: [MustardTask]) -> [MustardTask] {
        tasks.filter { $0.status == .done }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Open tasks with no list — the unfiled bucket, oldest first.
    public static func unfiled(_ all: [MustardTask]) -> [MustardTask] {
        all.filter { $0.list == nil && $0.status.isOpen }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Count of open tasks filed into `list`.
    public static func openCount(for list: TaskList, in all: [MustardTask]) -> Int {
        all.lazy.filter { $0.list === list && $0.status.isOpen }.count
    }

    /// Count of open tasks across all lists belonging to `area` (matched by the
    /// task's `list.area`, so area-less lists never contribute).
    public static func openCount(for area: Area, in all: [MustardTask]) -> Int {
        all.lazy.filter { $0.status.isOpen && $0.list?.area === area }.count
    }

    /// Count of open, unfiled tasks (for the "Unfiled" sidebar entry).
    public static func unfiledCount(_ all: [MustardTask]) -> Int {
        all.lazy.filter { $0.list == nil && $0.status.isOpen }.count
    }

    /// Areas sorted by name (localized, case-insensitive), then createdAt.
    public static func sortedAreas(_ areas: [Area]) -> [Area] {
        areas.sorted { Self.before($0.name, $1.name, $0.createdAt, $1.createdAt) }
    }

    /// Lists sorted by name (localized, case-insensitive), then createdAt.
    public static func sortedLists(_ lists: [TaskList]) -> [TaskList] {
        lists.sorted { Self.before($0.name, $1.name, $0.createdAt, $1.createdAt) }
    }

    /// Lists with no area — the area-less group, sorted.
    public static func areaLessLists(_ lists: [TaskList]) -> [TaskList] {
        sortedLists(lists.filter { $0.area == nil })
    }

    /// Name-first ordering, createdAt as the stable tie-break.
    private static func before(_ n1: String, _ n2: String, _ c1: Date, _ c2: Date) -> Bool {
        switch n1.localizedCaseInsensitiveCompare(n2) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return c1 < c2
        }
    }
}
