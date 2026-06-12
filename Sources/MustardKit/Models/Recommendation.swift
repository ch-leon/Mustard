import Foundation
import SwiftData

public enum RecommendationDecision: String, Codable, CaseIterable {
    case pending, approved, denied, scheduled, selfExecute
}

public enum ExecutionState: String, Codable, CaseIterable {
    case idle, running, finished, failed
}

@Model
public final class Recommendation {
    public var title: String = ""
    public var body: String = ""
    public var proposedActionType: String = "vault_note"
    public var decisionRaw: String = RecommendationDecision.pending.rawValue
    public var executionStateRaw: String = ExecutionState.idle.rawValue
    public var vaultPath: String = ""
    public var createdAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \OutputCard.recommendation)
    public var outputs: [OutputCard]? = []

    public var decision: RecommendationDecision {
        get { RecommendationDecision(rawValue: decisionRaw) ?? .pending }
        set { decisionRaw = newValue.rawValue }
    }

    public var executionState: ExecutionState {
        get { ExecutionState(rawValue: executionStateRaw) ?? .idle }
        set { executionStateRaw = newValue.rawValue }
    }

    public init(title: String = "", body: String = "", actionType: String = "vault_note", vaultPath: String = "") {
        self.title = title
        self.body = body
        self.proposedActionType = actionType
        self.vaultPath = vaultPath
        self.createdAt = .now
    }
}

public enum ReviewStatus: String, Codable, CaseIterable {
    case pending, accepted, revised, discarded
}

@Model
public final class OutputCard {
    public var content: String = ""
    public var kind: String = "summary"
    public var reviewRaw: String = ReviewStatus.pending.rawValue
    public var createdAt: Date = Date.now
    public var recommendation: Recommendation?

    public var review: ReviewStatus {
        get { ReviewStatus(rawValue: reviewRaw) ?? .pending }
        set { reviewRaw = newValue.rawValue }
    }

    public init(content: String = "", kind: String = "summary", recommendation: Recommendation? = nil) {
        self.content = content
        self.kind = kind
        self.recommendation = recommendation
        self.createdAt = .now
    }
}
