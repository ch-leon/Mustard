import Foundation

/// Pure selection helpers for the Agent recommendations master-detail list.
public enum RecommendationSelection {
    /// Which recommendation should be selected, given the current selection and the
    /// live pending queue: keep the current one if it's still pending, otherwise fall
    /// back to the top of the queue (or nil when empty). Identity-based (`===`) so it
    /// never dereferences a recommendation that has left the queue.
    public static func nextSelection(current: Recommendation?, pending: [Recommendation]) -> Recommendation? {
        if let current, pending.contains(where: { $0 === current }) { return current }
        return pending.first
    }

    /// Whether selecting `rec` should also auto-open the source panel: only when the
    /// setting is on AND the rec resolves to an http(s) source link.
    public static func shouldAutoOpenSource(settingOn: Bool, rec: Recommendation?) -> Bool {
        guard settingOn, let rec else { return false }
        return SourceLink(from: rec) != nil
    }
}
