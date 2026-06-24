import Foundation

/// Pure mapping from a source to how the triage UI badges it. Vault stays quiet (plain
/// text line, no pill); non-vault sources get an icon + label. Keeps the view dumb.
public struct SourceBadge: Equatable {
    public let symbol: String   // SF Symbol name
    public let label: String
    public let isQuiet: Bool     // vault → true: no pill, matches today's calm look

    public static func badge(for source: SourceID) -> SourceBadge {
        switch source {
        case .gmail:    SourceBadge(symbol: "envelope.fill",      label: "Gmail",    isQuiet: false)
        case .vault:    SourceBadge(symbol: "books.vertical",     label: "Vault",    isQuiet: true)
        case .jira:     SourceBadge(symbol: "ticket",             label: "Jira",     isQuiet: false)
        case .shortcut: SourceBadge(symbol: "lasso",              label: "Shortcut", isQuiet: false)
        }
    }

    /// Tolerant entry point for the stored `Recommendation.source` string.
    public static func badge(forRaw raw: String) -> SourceBadge {
        badge(for: SourceID(rawValue: raw) ?? .vault)
    }
}
