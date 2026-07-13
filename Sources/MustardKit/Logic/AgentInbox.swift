import Foundation

/// What's waiting on the human from the agent right now — the count behind the
/// sidebar badge, the co-pilot dock, and Today's "Agent has N things for you" nudge
/// (BAK-104). Pure + tested; respects snooze/ignore via `RecommendationQueue.pending`.
public enum AgentInbox {
    /// Pending (un-snoozed, non-ignored) recommendations + tasks needing input or review.
    public static func waitingCount(
        recommendations: [Recommendation], tasks: [MustardTask], now: Date = .now
    ) -> Int {
        pendingRecCount(recommendations, now: now) + attentionTaskCount(tasks)
    }

    /// Pending (un-snoozed, non-ignored) recommendations awaiting triage.
    public static func pendingRecCount(_ recommendations: [Recommendation], now: Date = .now) -> Int {
        RecommendationQueue.pending(recommendations, now: now).count
    }

    /// Agent tasks awaiting your answer or output review (Needs You + Needs Review).
    public static func attentionTaskCount(_ tasks: [MustardTask]) -> Int {
        tasks.filter { $0.stage == .needsInput || $0.stage == .needsReview }.count
    }

    /// The two attention groups for the unified Agent Console queue: questions (Needs You)
    /// and outputs (Needs Review), each oldest-first so the longest-waiting item leads.
    public struct AgentAttention {
        public let questions: [MustardTask]
        public let reviews: [MustardTask]
    }

    public static func attention(_ tasks: [MustardTask]) -> AgentAttention {
        AgentAttention(
            questions: tasks.filter { $0.stage == .needsInput }.sorted { $0.createdAt < $1.createdAt },
            reviews: tasks.filter { $0.stage == .needsReview }.sorted { $0.createdAt < $1.createdAt }
        )
    }

    /// Co-pilot dock text (BAK-106): "{N} recommendation(s) and {M} item(s) waiting
    /// on you", or "All clear — nothing waiting on you" when both are zero.
    public static func dockText(recs: Int, items: Int) -> String {
        guard recs > 0 || items > 0 else { return "All clear — nothing waiting on you" }
        var parts: [String] = []
        if recs > 0 { parts.append("\(recs) recommendation\(recs == 1 ? "" : "s")") }
        if items > 0 { parts.append("\(items) item\(items == 1 ? "" : "s")") }
        return parts.joined(separator: " and ") + " waiting on you"
    }
}
