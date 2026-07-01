import Foundation

/// What the agent proposes to do with a recommendation. Raw values are the
/// tokens stored on `Recommendation.proposedActionType` and emitted by the sweep.
public enum RecommendationAction: String, CaseIterable, Identifiable {
    case draftEmail = "draft_email"
    case draftSlack = "draft_slack"
    case createTask = "create_task"
    case vaultNote = "vault_note"
    case ticket = "ticket_write"
    case fyi = "fyi"
    case ignore = "ignore"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .draftEmail: "Draft email"
        case .draftSlack: "Draft Slack"
        case .createTask: "Create task"
        case .vaultNote: "Update vault"
        case .ticket: "Create Shortcut"
        case .fyi: "FYI"
        case .ignore: "Ignore"
        }
    }

    /// Outward-facing actions that always require explicit sign-off.
    public var isGated: Bool {
        switch self {
        case .draftEmail, .draftSlack, .ticket: true
        default: false
        }
    }

    public static func from(_ raw: String) -> RecommendationAction {
        RecommendationAction(rawValue: raw) ?? .vaultNote
    }
}
