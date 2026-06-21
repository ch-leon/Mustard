import Foundation

/// What stage a delegated task is at, derived from its linked Recommendation +
/// latest OutputCard. Drives the row badge ("Agent working…" / "Awaiting review").
public enum DelegationPhase: Equatable {
    case none            // not delegated → no badge
    case proposed        // queued for your approval (Manual/Supervised)
    case working         // claude -p is running
    case awaitingReview  // output produced, waiting for Accept/Revise/Discard
    case done            // accepted → task complete

    public var label: String? {
        switch self {
        case .none: nil
        case .proposed: "Proposed"
        case .working: "Agent working…"
        case .awaitingReview: "Awaiting review"
        case .done: "Done by agent"
        }
    }
}

extension DelegationPhase {
    /// Pure resolver over primitives (testable without a model context).
    public static func resolve(
        isDelegated: Bool, executionState: ExecutionState?,
        decision: RecommendationDecision?, latestReview: ReviewStatus?, taskDone: Bool
    ) -> DelegationPhase {
        guard isDelegated else { return .none }
        if taskDone { return .done }
        if executionState == .running { return .working }
        if latestReview == .pending { return .awaitingReview }
        if decision == .pending { return .proposed }
        // Approved + finished but no pending output (e.g. already reviewed) → no badge.
        return .none
    }

    /// Live-task glue used by the views.
    public static func of(_ task: MustardTask) -> DelegationPhase {
        let rec = task.delegation
        return resolve(
            isDelegated: task.owner == .agent && rec != nil,
            executionState: rec?.executionState,
            decision: rec?.decision,
            latestReview: rec?.outputs?.sorted(by: { $0.createdAt < $1.createdAt }).last?.review,
            taskDone: task.status == .done
        )
    }
}
