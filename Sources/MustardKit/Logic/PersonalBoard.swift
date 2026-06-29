import Foundation

/// Area filter for the board. `personal` matches the Errands/Reading lists.
public enum BoardArea: Equatable {
    case all, area(String), personal
}

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

    /// Legacy column move by status. Renamed to avoid overload ambiguity with the
    /// stage-based `move` (shared case names like `.done`). Removed with the old API.
    public static func moveStatus(_ task: MustardTask, to status: TaskStatus, now: Date = .now) {
        if status == .done {
            task.markDone(now: now)
        } else {
            task.status = status
            task.completedAt = nil
        }
    }

    // MARK: - Stage-based board (BAK-76)
    // New owner-segmented API. Coexists with the legacy status API above until the
    // BoardView rebuild (BAK-79) switches over; the legacy functions go then.

    /// Columns shown for a given owner view.
    public static func columns(for view: BoardOwnerView) -> [TaskStage] { view.columns }

    /// Tasks in a stage within the current owner + area scope, oldest first
    /// (done by most-recently-completed).
    public static func tasks(_ all: [MustardTask], in stage: TaskStage,
                             view: BoardOwnerView, area: BoardArea) -> [MustardTask] {
        all.filter { $0.stage == stage && ownerOK($0, view) && areaOK($0, area) }
            .sorted { sortKey($0) < sortKey($1) }
    }

    /// Items needing you (needs approval + needs review) within the current scope.
    public static func waitingCount(_ all: [MustardTask], view: BoardOwnerView, area: BoardArea) -> Int {
        all.filter { ($0.stage == .needsApproval || $0.stage == .needsReview)
            && ownerOK($0, view) && areaOK($0, area) }.count
    }

    /// Unfiltered agent attention badge (sidebar): needs approval + needs review.
    public static func agentBadge(_ all: [MustardTask]) -> Int {
        all.filter { $0.stage == .needsApproval || $0.stage == .needsReview }.count
    }

    /// Done beyond the visible limit, within scope — the "+N older" remainder.
    public static func olderDoneCount(_ all: [MustardTask], view: BoardOwnerView,
                                      area: BoardArea, limit: Int = doneColumnLimit) -> Int {
        max(0, tasks(all, in: .done, view: view, area: area).count - limit)
    }

    /// Apply a column move by stage: set stage, keep completedAt consistent with done.
    public static func move(_ task: MustardTask, to stage: TaskStage, now: Date = .now) {
        if stage == .done { task.markDone(now: now) }
        else { task.stage = stage; task.completedAt = nil }
    }

    /// Card owner toggle: to agent → forAgent; to me → planned; done keeps its stage.
    public static func reassign(_ task: MustardTask, to owner: TaskOwner) {
        guard task.owner != owner else { return }
        task.owner = owner
        if task.stage != .done { task.stage = owner == .agent ? .forAgent : .planned }
    }

    private static func ownerOK(_ t: MustardTask, _ view: BoardOwnerView) -> Bool {
        switch view {
        case .everyone: return true
        case .mine: return t.owner == .me
        case .agent: return t.owner == .agent
        }
    }

    private static func areaOK(_ t: MustardTask, _ area: BoardArea) -> Bool {
        switch area {
        case .all: return true
        case .area(let name): return t.list?.area?.name == name
        case .personal:
            let n = t.list?.area?.name
            return n == "Errands" || n == "Reading"
        }
    }

    /// Done sorts by completedAt desc; everything else by createdAt asc.
    private static func sortKey(_ t: MustardTask) -> Double {
        t.stage == .done ? -(t.completedAt ?? .distantPast).timeIntervalSince1970
                         : t.createdAt.timeIntervalSince1970
    }
}
