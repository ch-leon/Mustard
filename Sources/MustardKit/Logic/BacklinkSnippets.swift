import Foundation

/// Recovers the containing-line snippet for a backlink row (BAK-151). The index
/// stores resolved forwardLinks but not the line; this re-scans the LINKING note's
/// content (from its contentSnapshot) for the first wikilink that resolves to the
/// target. Pure; skips code fences exactly like WikilinkIndex extraction. Wikilink
/// grammar lives in `WikilinkSyntax` (one definition, three consumers).
public enum BacklinkSnippets {
    /// Convenience over the resolver overload — builds the resolver ONCE for this
    /// call. Callers scanning many notes against one candidate set (the backlinks
    /// panel) should hoist `WikilinkIndex.resolver(paths:)` and use the overload.
    public static func snippet(in content: String, targetPath: String, candidatePaths: [String]) -> String? {
        snippet(in: content, targetPath: targetPath, resolve: WikilinkIndex.resolver(paths: candidatePaths))
    }

    /// First line of `content` (frontmatter-stripped internally) containing a
    /// wikilink that `resolve` maps to `targetPath`; trimmed. Nil when none.
    public static func snippet(in content: String, targetPath: String,
                               resolve: (String) -> String?) -> String? {
        let body = Frontmatter.parse(content).body
        var inFence = false
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            // Same fence rule as WikilinkIndex extraction: a line whose trimmed
            // start is ``` toggles the fenced state and is itself skipped.
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }

            for occ in WikilinkSyntax.occurrences(in: line) {
                if resolve(occ.target) == targetPath {
                    return line.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
}
