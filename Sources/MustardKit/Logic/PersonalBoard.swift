import Foundation

/// Area filter for the board. `personal` matches the Errands/Reading lists.
public enum BoardArea: Equatable {
    case all, area(String), personal
}

/// Grouping logic for the personal Kanban board (owner == me).
public enum PersonalBoard {
    /// How many completed tasks the Done column keeps visible. The rest collapse
    /// into a "+N older" footer so the board can't grow unbounded as done tasks
    /// accumulate — a count cap, not a date window, so it bounds the column
    /// regardless of how completion timestamps cluster.
    public static let doneColumnLimit = 15

    // MARK: - Stage-based board (BAK-76)
    // Owner-segmented API keyed on `TaskStage` (the source of truth). The legacy
    // `status`-based functions were retired in BAK-80.

    /// Columns shown for a given owner view.
    public static func columns(for view: BoardOwnerView) -> [TaskStage] { view.columns }

    /// The two gate columns shown when the board is focused to the review queue
    /// ("N waiting on you" → Exit review queue, BAK-101).
    public static let gateStages: [TaskStage] = [.needsApproval, .needsReview]

    /// Whether an empty column should auto-collapse to a thin strip (BAK-102): only
    /// in the Everyone lens, never while review-focused, and not if the user has
    /// manually expanded it. Mine/Agent lenses keep empty columns full-width.
    public static func shouldCollapseEmpty(view: BoardOwnerView, isEmpty: Bool,
                                           expanded: Bool, reviewFocus: Bool) -> Bool {
        view == .everyone && !reviewFocus && isEmpty && !expanded
    }

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

    /// Target stage when the human approves a gate (BAK-100). needsApproval → queued
    /// (gated, will run) or needsReview (non-gated, straight to output review);
    /// needsReview → done. Nil when the task isn't on a gate stage. Reject/Discard
    /// (deletion) and the reverse transitions (Hold→needsApproval, Request changes→
    /// queued) are handled by the caller via `move`/delete.
    public static func approveTarget(for task: MustardTask) -> TaskStage? {
        switch task.stage {
        case .needsApproval: return task.isGated ? .queued : .needsReview
        case .needsReview: return .done
        default: return nil
        }
    }

    /// Whether a task may be handed to the agent (For Agent / Queued). Requires a
    /// client area: the bridge export filters by area, so an area-less hand-off would
    /// silently never route (BAK-90). The single gate the views + `delegate` check.
    public static func canHandOffToAgent(_ task: MustardTask) -> Bool {
        task.list?.area != nil
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
