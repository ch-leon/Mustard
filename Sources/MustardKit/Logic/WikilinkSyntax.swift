import Foundation

/// THE wikilink syntax definition — one place, three consumers: `WikilinkIndex`
/// (link graph), `MarkdownBlocks` (preview runs), `BacklinkSnippets` (backlink
/// rows). Previously each carried a character-identical copy of the pattern and
/// drift would have been silent; any change to what counts as a wikilink must
/// happen here and nowhere else.
public enum WikilinkSyntax {
    /// One parsed occurrence on a line. `target`/`alias` are whitespace-trimmed;
    /// `range` is the FULL match range in NSString (UTF-16) coordinates, so callers
    /// can splice the surrounding literal text (MarkdownBlocks.runs).
    public struct Occurrence: Equatable {
        public let target: String
        public let alias: String?
        public let range: NSRange
    }

    /// `!?\[\[([^\]\|#]+)(#[^\]\|]*)?(\|([^\]]+))?\]\]` — matches [[T]], [[T#H]],
    /// [[T|alias]], ![[T]]. Group 1 is the target, group 4 the alias.
    public static let pattern = #"!?\[\[([^\]\|#]+)(#[^\]\|]*)?(\|([^\]]+))?\]\]"#

    public static let regex = try! NSRegularExpression(pattern: pattern)

    /// All wikilinks on one line, in occurrence order. Targets and aliases are
    /// trimmed with `.whitespaces`; empty-after-trim targets (`[[ ]]`) are DROPPED —
    /// consumers uniformly treat them as not-a-link (plain text / no graph edge).
    public static func occurrences(in line: String) -> [Occurrence] {
        let ns = line as NSString
        var result: [Occurrence] = []
        for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let target = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { continue }
            let aliasRange = match.range(at: 4)
            let alias = aliasRange.location == NSNotFound
                ? nil
                : ns.substring(with: aliasRange).trimmingCharacters(in: .whitespaces)
            result.append(Occurrence(target: target, alias: alias, range: match.range))
        }
        return result
    }
}
