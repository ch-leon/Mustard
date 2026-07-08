import Foundation

/// Derives the *logical* source of a Gmail-delivered rec from its provenance text.
/// Jira/Shortcut notifications arrive over Gmail; the meaningful source is the system
/// the notification is about. Pure + tested. Only `gmail` is ever reclassified —
/// vault/delegated/already-classified transports pass through unchanged.
public enum SourceClassifier {
    public static func logicalSource(
        transport: SourceID, sourceContext: String, labels: [String] = []
    ) -> SourceID {
        guard transport == .gmail else { return transport }
        // Gmail labels are ground truth: Jira/Shortcut robots auto-filter into a label,
        // while a human reply that merely *mentions* a ticket key does not. When labels
        // are captured we trust them and never consult the content heuristics — that is
        // what stops a real reply (e.g. "re DLA-5598") being mislabeled as Jira.
        if !labels.isEmpty { return source(fromLabels: labels) ?? .gmail }
        // Legacy recs (no labels captured) → provenance-text heuristics.
        let ctx = sourceContext.trimmingCharacters(in: .whitespaces).lowercased()
        if ctx.hasPrefix("jira") { return .jira }
        if ctx.hasPrefix("shortcut") { return .shortcut }
        // Jira-style ticket key (e.g. DLA-5280) anywhere in the provenance → Jira.
        if sourceContext.range(of: #"[A-Z]{2,}-\d+"#, options: .regularExpression) != nil { return .jira }
        return .gmail
    }

    /// Map the first Jira/Shortcut label to its logical source. `Jira`/`Jira Updates`
    /// → Jira; `Shortcut Notifications` → Shortcut. Non-source labels (project tags,
    /// system labels) return `nil` so the caller can keep the item as Gmail.
    private static func source(fromLabels labels: [String]) -> SourceID? {
        for label in labels {
            let l = label.lowercased()
            if l.hasPrefix("jira") { return .jira }
            if l.contains("shortcut") { return .shortcut }
        }
        return nil
    }
}
