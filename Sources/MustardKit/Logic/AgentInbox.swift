import Foundation

/// What's waiting on the human from the agent right now — the count behind the
/// sidebar badge, the co-pilot dock, and Today's "Agent has N things for you" nudge
/// (BAK-104). Pure + tested; respects snooze/ignore via `RecommendationQueue.pending`.
public enum AgentInbox {
    /// Pending (un-snoozed, non-ignored) recommendations + tasks at the review gate.
    public static func waitingCount(
        recommendations: [Recommendation], tasks: [MustardTask], now: Date = .now
    ) -> Int {
        RecommendationQueue.pending(recommendations, now: now).count
            + tasks.filter { $0.stage == .needsReview }.count
    }
}
