import Foundation

/// Decides whether an ingested `SourceProposal` is a new event worth inserting,
/// or a duplicate to drop. Pure + tested — the idempotency guarantee that lets a
/// source sweep run many times a day without piling up cards.
public enum SourceDedupe {
    /// Reject when:
    ///  1. **Exact event already seen** — an existing rec shares `(source, sourceEventID)`,
    ///     regardless of its decision/execution state. The user has seen this event.
    ///  2. **Un-triaged duplicate** — an existing *pending* rec shares
    ///     `(source, sourceItemID, actionType)`. Scoped to `pending` so that once an
    ///     item is decided, a genuinely new event (new `sourceEventID`) still surfaces.
    public static func shouldInsert(_ p: SourceProposal, against existing: [Recommendation]) -> Bool {
        let src = p.source.rawValue
        if existing.contains(where: { $0.source == src && $0.sourceEventID == p.sourceEventID }) {
            return false
        }
        if existing.contains(where: {
            $0.decision == .pending && $0.source == src
                && $0.sourceItemID == p.sourceItemID && $0.proposedActionType == p.actionType
        }) {
            return false
        }
        return true
    }
}
