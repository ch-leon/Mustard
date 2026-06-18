import Foundation

/// Which source produced a proposal. String-backed so it maps cleanly onto
/// `Recommendation.source` (a String column) for dedupe.
public enum SourceID: String, Codable, CaseIterable, Sendable {
    case gmail
    case vault
}

/// A source agent's output: a recommendation draft plus the provenance needed to
/// dedupe it. Pure value type. Produced by `VaultSweep` (local) and the cloud
/// scout's `_inbox/` files (ingested Mac-side).
public struct SourceProposal: Equatable, Sendable, Codable {
    public let source: SourceID
    /// Which project / knowledge base this belongs to (the KB folder name). Keeps
    /// dedupe and grounding isolated per project — identical note text in two KBs
    /// gets distinct identity, so one project's note can never collapse into another.
    public let project: String
    /// Durable parent object (email thread, or vault content hash).
    public let sourceItemID: String
    /// Triggering event (email message id, or deterministic vault content hash).
    public let sourceEventID: String
    public let sourceContext: String
    public let sourceURL: String?
    public let occurredAt: Date?
    public let title: String
    public let body: String
    public let actionType: String
    public let confidence: Double
    public let reasoning: String
    public let draft: String

    public init(
        source: SourceID, project: String = "", sourceItemID: String, sourceEventID: String,
        sourceContext: String = "", sourceURL: String? = nil, occurredAt: Date? = nil,
        title: String, body: String = "", actionType: String = "vault_note",
        confidence: Double = 0.5, reasoning: String = "", draft: String = ""
    ) {
        self.source = source
        self.project = project
        self.sourceItemID = sourceItemID
        self.sourceEventID = sourceEventID
        self.sourceContext = sourceContext
        self.sourceURL = sourceURL
        self.occurredAt = occurredAt
        self.title = title
        self.body = body
        self.actionType = actionType
        self.confidence = confidence
        self.reasoning = reasoning
        self.draft = draft
    }
}

public extension SourceProposal {
    /// Map a vault sweep proposal into a `SourceProposal`, deriving a **stable,
    /// project-qualified** content hash as its identity so (a) repeated scheduled
    /// sweeps don't duplicate unchanged suggestions, and (b) identical note text in
    /// two different KBs never collides in dedupe.
    init(vault p: VaultSweep.Proposal, project: String) {
        let hash = SourceProposal.stableHash("\(project)\n\(p.title)\n\(p.body)\n\(p.actionType)\n\(p.draft)")
        self.init(
            source: .vault, project: project, sourceItemID: hash, sourceEventID: hash,
            title: p.title, body: p.body, actionType: p.actionType,
            confidence: p.confidence, reasoning: p.reasoning, draft: p.draft
        )
    }

    /// Deterministic FNV-1a hash, hex-encoded. Process-stable across launches —
    /// unlike Swift's seeded `String.hashValue`, which must never key persisted
    /// dedupe identity.
    static func stableHash(_ s: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
