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
    // Rich triage fields (Plan 6): provenance, agent signal, editable draft.
    public var confidence: Double = 0.5
    public var reasoning: String = ""
    public var draft: String = ""
    public var source: String = "vault"
    /// Project / knowledge base (KB folder name) — isolates dedupe, grounding, and
    /// UI per project (multi-project). Defaulted → CloudKit-compatible (ADR-0001).
    public var project: String = ""
    public var sourceContext: String = ""
    public var sourceURL: String?
    /// Raw source content (e.g. the original email body) so it can be read before the
    /// proposed draft. Optional → CloudKit-safe default (ADR-0001); vault recs leave it nil.
    public var originalSource: String?
    // Ingestion provenance (Plan 7): stable identity for dedupe + when it occurred.
    // Optional → auto-nil default keeps the model CloudKit-compatible (ADR-0001).
    public var sourceItemID: String?
    public var sourceEventID: String?
    public var occurredAt: Date?
    public var comment: String = ""
    public var snoozedUntil: Date?
    public var createdAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \OutputCard.recommendation)
    public var outputs: [OutputCard]? = []
    /// The task this recommendation was created to action (set when you delegate a
    /// task to the agent). Nil for sweep/inbox recs. Inverse of `MustardTask.delegation`.
    /// Optional → CloudKit-safe default (ADR-0001).
    public var task: MustardTask?

    public var decision: RecommendationDecision {
        get { RecommendationDecision(rawValue: decisionRaw) ?? .pending }
        set { decisionRaw = newValue.rawValue }
    }

    public var executionState: ExecutionState {
        get { ExecutionState(rawValue: executionStateRaw) ?? .idle }
        set { executionStateRaw = newValue.rawValue }
    }

    public init(
        title: String = "", body: String = "", actionType: String = "vault_note",
        vaultPath: String = "", confidence: Double = 0.5, reasoning: String = "",
        draft: String = "", source: String = "vault", sourceContext: String = "",
        sourceURL: String? = nil
    ) {
        self.title = title
        self.body = body
        self.proposedActionType = actionType
        self.vaultPath = vaultPath
        self.confidence = confidence
        self.reasoning = reasoning
        self.draft = draft
        self.source = source
        self.sourceContext = sourceContext
        self.sourceURL = sourceURL
        self.createdAt = .now
    }

    /// Build a recommendation from an ingested `SourceProposal`, stamping its
    /// source identity (Plan 7). Used by the shared insert pipeline.
    public convenience init(from p: SourceProposal, vaultPath: String) {
        self.init(
            title: p.title, body: p.body, actionType: p.actionType, vaultPath: vaultPath,
            confidence: p.confidence, reasoning: p.reasoning, draft: p.draft,
            source: p.source.rawValue, sourceContext: p.sourceContext, sourceURL: p.sourceURL
        )
        self.project = p.project
        self.sourceItemID = p.sourceItemID
        self.sourceEventID = p.sourceEventID
        self.occurredAt = p.occurredAt
        self.originalSource = p.originalSource
    }

    public var action: RecommendationAction {
        get { RecommendationAction.from(proposedActionType) }
        set { proposedActionType = newValue.rawValue }
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
