import Foundation

/// Where an approved/scheduled recommendation lands on the board.
public enum RecommendationPromotion {
    public struct Plan: Equatable { public let stage: TaskStage; public let owner: TaskOwner }

    /// In-vault actions (vault note, create task) can run headless → straight to Done.
    /// Outward/connector actions queue for the decoupled session. Schedule keeps it
    /// yours (a scheduled task); "I'll do it" makes it a planned task of yours.
    public static func plan(action: RecommendationAction, decision: RecommendationDecision) -> Plan {
        switch decision {
        case .scheduled: return Plan(stage: .scheduled, owner: .me)
        case .selfExecute: return Plan(stage: .planned, owner: .me)
        case .approved:
            let inVault = (action == .vaultNote || action == .createTask)
            return Plan(stage: inVault ? .done : .queued, owner: .agent)
        default: return Plan(stage: .inbox, owner: .me)
        }
    }
}
