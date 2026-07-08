import Foundation

/// The triage queue: which recommendations are waiting on you right now. Pure + tested
/// so the "ignore vanishes" + snooze rules live in one place the view just renders.
public enum RecommendationQueue {
    public static func pending(_ recs: [Recommendation], now: Date) -> [Recommendation] {
        recs.filter { rec in
            guard rec.decision == .pending, rec.action != .ignore else { return false }
            // ignored items exist for dedupe/audit but never surface (checked above)
            if let snoozedUntil = rec.snoozedUntil {
                return snoozedUntil <= now
            }
            return true
        }
    }
}
