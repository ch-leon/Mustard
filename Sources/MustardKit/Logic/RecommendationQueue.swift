import Foundation

/// The triage queue: which recommendations are waiting on you right now. Pure + tested
/// so the "ignore vanishes" + snooze rules live in one place the view just renders.
public enum RecommendationQueue {
    public static func pending(_ recs: [Recommendation], now: Date) -> [Recommendation] {
        recs.filter {
            $0.decision == .pending
                && ($0.snoozedUntil == nil || $0.snoozedUntil! <= now)
                && $0.action != .ignore   // ignored items exist for dedupe/audit but never surface
        }
    }
}
