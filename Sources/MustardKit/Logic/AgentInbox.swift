import Foundation

/// What's waiting on the human from the agent right now — the count behind the
/// sidebar badge, the co-pilot dock, and Today's "Agent has N things for you" nudge
/// (BAK-104). Pure + tested; respects snooze/ignore via `RecommendationQueue.pending`.
public enum AgentInbox {
    /// Pending (un-snoozed, non-ignored) recommendations + tasks needing input or review.
    public static func waitingCount(
        recommendations: [Recommendation], tasks: [MustardTask], now: Date = .now
    ) -> Int {
        pendingRecCount(recommendations, now: now) + outputCount(tasks)
    }

    /// Pending (un-snoozed, non-ignored) recommendations awaiting triage.
    public static func pendingRecCount(_ recommendations: [Recommendation], now: Date = .now) -> Int {
        RecommendationQueue.pending(recommendations, now: now).count
    }

    /// Agent tasks awaiting your answer or output review (Needs You + Needs Review).
    public static func outputCount(_ tasks: [MustardTask]) -> Int {
        tasks.filter { $0.stage == .needsInput || $0.stage == .needsReview }.count
    }

    /// Co-pilot dock text (BAK-106): "{N} recommendation(s) and {M} output(s) waiting
    /// on you", or "All clear — nothing waiting on you" when both are zero.
    public static func dockText(recs: Int, outputs: Int) -> String {
        guard recs > 0 || outputs > 0 else { return "All clear — nothing waiting on you" }
        var parts: [String] = []
        if recs > 0 { parts.append("\(recs) recommendation\(recs == 1 ? "" : "s")") }
        if outputs > 0 { parts.append("\(outputs) output\(outputs == 1 ? "" : "s")") }
        return parts.joined(separator: " and ") + " waiting on you"
    }
}
