import Foundation

/// Derives the *logical* source of a Gmail-delivered rec from its provenance text.
/// Jira/Shortcut notifications arrive over Gmail; the meaningful source is the system
/// the notification is about. Pure + tested. Only `gmail` is ever reclassified —
/// vault/delegated/already-classified transports pass through unchanged.
public enum SourceClassifier {
    public static func logicalSource(transport: SourceID, sourceContext: String) -> SourceID {
        guard transport == .gmail else { return transport }
        let ctx = sourceContext.trimmingCharacters(in: .whitespaces).lowercased()
        if ctx.hasPrefix("jira") { return .jira }
        if ctx.hasPrefix("shortcut") { return .shortcut }
        // Jira-style ticket key (e.g. DLA-5280) anywhere in the provenance → Jira.
        if sourceContext.range(of: #"[A-Z]{2,}-\d+"#, options: .regularExpression) != nil { return .jira }
        return .gmail
    }
}
