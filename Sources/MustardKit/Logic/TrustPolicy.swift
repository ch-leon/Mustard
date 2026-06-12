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
    public static let gatedActionTypes: Set<String> = ["email_send", "ticket_write", "slack_post"]

    public static func isGated(actionType: String) -> Bool {
        gatedActionTypes.contains(actionType)
    }

    /// May this recommendation execute without a manual Approve?
    public static func shouldAutoApprove(actionType: String, trust: TrustLevel) -> Bool {
        !isGated(actionType: actionType) && trust.rank >= TrustLevel.supervised.rank
    }

    /// May this execution's output be accepted without a manual Accept?
    public static func shouldAutoAccept(actionType: String, trust: TrustLevel) -> Bool {
        !isGated(actionType: actionType) && trust.rank >= TrustLevel.trusted.rank
    }
}
