import Foundation

/// A provenance header plus the recommendations that share one source item (e.g. one
/// email thread). Option A: grouping is a *view* over recs — no persisted entity.
public struct RecGroup: Identifiable {
    public let id: String
    public let members: [Recommendation]
    /// True when one source produced several recs → render the shared header + fan-out.
    public var isMultiSource: Bool { members.count > 1 }
    /// Provenance comes from any member (they share the source). `grouped(_:)` never
    /// produces an empty `members`, but the fallback keeps this total without `!`.
    public var header: Recommendation { members.first ?? Recommendation(title: "") }
}

public enum SourceGrouping {
    /// Group recs so multiple recs from one source render under a single header. Recs
    /// with a shared non-empty `sourceItemID` group together; everything else is a
    /// singleton. First-appearance order is preserved.
    public static func grouped(_ recs: [Recommendation]) -> [RecGroup] {
        var order: [String] = []
        var buckets: [String: [Recommendation]] = [:]
        for (i, rec) in recs.enumerated() {
            let key: String
            if let sourceItemID = rec.sourceItemID, !sourceItemID.isEmpty {
                key = sourceItemID
            } else {
                key = "solo-\(i)"
            }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(rec)
        }
        return order.map { RecGroup(id: $0, members: buckets[$0] ?? []) }
    }
}
