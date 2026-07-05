import Foundation

/// Recovers the containing-line snippet for a backlink row (BAK-151). The index
/// stores resolved forwardLinks but not the line; this re-scans the LINKING note's
/// content (from its contentSnapshot) for the first wikilink that resolves to the
/// target. Pure; skips code fences exactly like WikilinkIndex extraction.
public enum BacklinkSnippets {
    /// First line of `content` (frontmatter-stripped internally) containing a
    /// wikilink that resolves to `targetPath` among `candidatePaths`; trimmed. Nil when none.
    public static func snippet(in content: String, targetPath: String, candidatePaths: [String]) -> String? {
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

            for target in wikilinkTargets(in: line) {
                if WikilinkIndex.resolve(target: target, in: candidatePaths) == targetPath {
                    return line.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    /// Same pattern as WikilinkIndex.linkRegex (which is private): matches [[T]],
    /// [[T#H]], [[T|alias]], ![[T]] and captures the bare target in group 1.
    private static let linkRegex = try! NSRegularExpression(
        pattern: #"!?\[\[([^\]\|#]+)(#[^\]\|]*)?(\|([^\]]+))?\]\]"#
    )

    /// Wikilink targets on a single line, in occurrence order, empty targets dropped.
    private static func wikilinkTargets(in line: String) -> [String] {
        let ns = line as NSString
        var targets: [String] = []
        for match in linkRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let target = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !target.isEmpty { targets.append(target) }
        }
        return targets
    }
}
