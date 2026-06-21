import Foundation

public enum TrustLevel: String, Codable, CaseIterable, Identifiable {
    case manual, supervised, trusted, autonomous
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .manual: "Manual"
        case .supervised: "Supervised"
        case .trusted: "Trusted"
        case .autonomous: "Autonomous"
        }
    }

    /// Higher = more autonomy. Used for threshold comparisons.
    public var rank: Int {
        switch self {
        case .manual: 0
        case .supervised: 1
        case .trusted: 2
        case .autonomous: 3
        }
    }

    public var blurb: String {
        switch self {
        case .manual: "You approve every recommendation."
        case .supervised: "Auto-runs non-gated work; you review the output."
        case .trusted: "Auto-runs and auto-accepts non-gated work."
        case .autonomous: "Fully hands-off except always-gated actions."
        }
    }
}

/// Decides how much the agent may do without you. Pure + tested.
public enum TrustPolicy {
    /// Actions that ALWAYS require explicit sign-off, regardless of trust.
    public static let gatedActionTypes: Set<String> = Set(
        RecommendationAction.allCases.filter(\.isGated).map(\.rawValue)
    )

    /// Confidence below this never auto-runs, even when Trusted/Autonomous.
    public static let autoConfidenceThreshold = 0.7

    public static func isGated(actionType: String) -> Bool {
        RecommendationAction.from(actionType).isGated
    }

    /// May this recommendation execute without a manual Approve?
    /// Requires: not gated, trust ≥ supervised, AND confidence ≥ threshold.
    public static func shouldAutoApprove(
        actionType: String, trust: TrustLevel, confidence: Double = 1.0
    ) -> Bool {
        !isGated(actionType: actionType)
            && trust.rank >= TrustLevel.supervised.rank
            && confidence >= autoConfidenceThreshold
    }

    /// May this execution's output be accepted without a manual Accept?
    public static func shouldAutoAccept(
        actionType: String, trust: TrustLevel, confidence: Double = 1.0
    ) -> Bool {
        !isGated(actionType: actionType)
            && trust.rank >= TrustLevel.trusted.rank
            && confidence >= autoConfidenceThreshold
    }

    /// May a *delegated* task run immediately (vs. queue for your approval)?
    /// Stricter than `shouldAutoApprove`: delegation only auto-runs at Trusted+ —
    /// Manual and Supervised both queue the proposal. Gated + confidence floor still apply.
    public static func shouldAutoRunDelegation(
        actionType: String, trust: TrustLevel, confidence: Double = 1.0
    ) -> Bool {
        !isGated(actionType: actionType)
            && trust.rank >= TrustLevel.trusted.rank
            && confidence >= autoConfidenceThreshold
    }
}
