import Foundation

/// Grouping logic for the personal Kanban board (owner == me).
public enum PersonalBoard {
    /// Columns left→right.
    public static let columns: [TaskStatus] = [.inbox, .planned, .inProgress, .done, .someday]

    /// My tasks in a given column, oldest first.
    public static func tasks(_ all: [MustardTask], status: TaskStatus) -> [MustardTask] {
        all.filter { $0.owner == .me && $0.status == status }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// How many completed tasks the Done column keeps visible. The rest collapse
    /// into a "+N older" footer so the board can't grow unbounded as done tasks
    /// accumulate — a count cap, not a date window, so it bounds the column
    /// regardless of how completion timestamps cluster.
    public static let doneColumnLimit = 15

    /// All my done tasks, most-recently-completed first.
    private static func allDone(_ all: [MustardTask]) -> [MustardTask] {
        all.filter { $0.owner == .me && $0.status == .done }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// The most-recent `limit` of my done tasks. Used in place of
    /// `tasks(_:status:)` for the Done column.
    public static func recentDone(_ all: [MustardTask], limit: Int = doneColumnLimit) -> [MustardTask] {
        Array(allDone(all).prefix(limit))
    }

    /// Count of my done tasks beyond the visible `limit` — the hidden remainder
    /// shown as "+N older" under the Done column.
    public static func olderDoneCount(_ all: [MustardTask], limit: Int = doneColumnLimit) -> Int {
        max(0, allDone(all).count - limit)
    }

    /// Apply a column move: set status, and keep completedAt consistent with done.
    public static func move(_ task: MustardTask, to status: TaskStatus, now: Date = .now) {
        if status == .done {
            task.markDone(now: now)
        } else {
            task.status = status
            task.completedAt = nil
        }
    }
}
