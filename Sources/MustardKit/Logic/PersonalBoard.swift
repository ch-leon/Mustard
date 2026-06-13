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
