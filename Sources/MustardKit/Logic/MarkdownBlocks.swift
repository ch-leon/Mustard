import Foundation

/// Pure preview parser for the Notes editor (design spec 2026-07-05, BAK-150).
/// Turns frontmatter-stripped markdown into an ordered list of render blocks,
/// isolating `[[wikilinks]]` as tappable inline runs. No filesystem, no clock,
/// no SwiftData — so it stays unit-tested (CLAUDE.md rule).
///
/// Scope is deliberately small (a calm light preview, not CommonMark): no tables,
/// footnotes, nested quotes, or setext headings. Inline **bold**/*italic* is NOT
/// parsed — the view renders `.text` runs through `AttributedString(markdown:)`,
/// so this parser only isolates BLOCK structure and wikilink tap targets.

public enum InlineRun: Equatable {
    case text(String)                             // may contain **md** — view renders via AttributedString
    case wikilink(target: String, alias: String?) // display alias ?? target
}

public enum MarkdownBlock: Equatable {
    case heading(level: Int, runs: [InlineRun])   // level 1...6
    case bullet(runs: [InlineRun], indent: Int)   // indent = leading spaces / 2
    case ordered(runs: [InlineRun], indent: Int)
    case quote(runs: [InlineRun])
    case code(String)                             // fence contents verbatim, no runs
    case rule                                     // --- / *** line
    case paragraph(runs: [InlineRun])             // consecutive non-blank lines joined by \n
}

public enum MarkdownBlocks {

    /// `body` is frontmatter-stripped content (callers use `Frontmatter.parse` first),
    /// so a lone `---` line is always a rule, never a YAML fence.
    public static func parse(_ body: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []

        // Paragraph buffer: raw lines accumulate, then join-with-\n → runs on flush,
        // so "a\nb" becomes a single `.text("a\nb")` run (paragraph test).
        var paragraphBuffer: [String] = []
        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: "\n")
            blocks.append(.paragraph(runs: runs(joined)))
            paragraphBuffer.removeAll()
        }

        // Fence state: an open fence swallows every line verbatim until the closing
        // fence (or EOF); the opening line's language tag is dropped.
        var inFence = false
        var fenceBuffer: [String] = []
        func flushFence() {
            blocks.append(.code(fenceBuffer.joined(separator: "\n")))
            fenceBuffer.removeAll()
        }

        for rawLine in body.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            // Fence toggle takes priority over everything else.
            if trimmed.hasPrefix("```") {
                if inFence {
                    flushFence()
                    inFence = false
                } else {
                    flushParagraph()
                    inFence = true
                }
                continue
            }
            if inFence {
                fenceBuffer.append(rawLine)
                continue
            }

            // Blank line separates paragraphs (and is otherwise inert).
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let block = blockLine(rawLine, trimmed: trimmed) {
                flushParagraph()
                blocks.append(block)
            } else {
                paragraphBuffer.append(rawLine)
            }
        }

        // EOF: an unterminated fence becomes whatever accumulated; flush any paragraph.
        if inFence {
            flushFence()
        } else {
            flushParagraph()
        }
        return blocks
    }

    /// Classifies one non-blank, non-fence line as a structural block, or nil if it's
    /// plain paragraph text. `trimmed` is the whitespace-trimmed form (computed once).
    private static func blockLine(_ line: String, trimmed: String) -> MarkdownBlock? {
        // Rule: a line that is exactly --- or *** (trimmed).
        if trimmed == "---" || trimmed == "***" {
            return .rule
        }

        // Heading: 1–6 leading '#' followed by a space.
        if let heading = headingBlock(trimmed) {
            return heading
        }

        // Quote: "> " prefix (one quote block per line is fine for a light preview).
        if trimmed.hasPrefix("> ") {
            return .quote(runs: runs(String(trimmed.dropFirst(2))))
        }

        // List items: measure indent from the raw line's leading spaces.
        let leadingSpaces = line.prefix { $0 == " " }.count
        let afterIndent = String(line.dropFirst(leadingSpaces))

        if afterIndent.hasPrefix("- ") || afterIndent.hasPrefix("* ") {
            return .bullet(runs: runs(String(afterIndent.dropFirst(2))), indent: leadingSpaces / 2)
        }
        if let rest = orderedRest(afterIndent) {
            return .ordered(runs: runs(rest), indent: leadingSpaces / 2)
        }

        return nil
    }

    /// `#{1,6} ` → heading of that level; the number itself is dropped. Seven or more
    /// hashes, or no trailing space, is not a heading.
    private static func headingBlock(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard hashes >= 1, hashes <= 6 else { return nil }
        let afterHashes = trimmed.dropFirst(hashes)
        guard afterHashes.hasPrefix(" ") else { return nil }
        return .heading(level: hashes, runs: runs(String(afterHashes.dropFirst())))
    }

    /// `\d+. ` → the text after the marker; nil otherwise. `1)` is deliberately NOT
    /// ordered (only the dot form), matching the light-preview scope.
    private static func orderedRest(_ text: String) -> String? {
        let digits = text.prefix { $0.isNumber }.count
        guard digits >= 1 else { return nil }
        let afterDigits = text.dropFirst(digits)
        guard afterDigits.hasPrefix(". ") else { return nil }
        return String(afterDigits.dropFirst(2))
    }

    /// `!?\[\[([^\]\|#]+)(#[^\]\|]*)?(\|([^\]]+))?\]\]` — matches [[T]], [[T#H]],
    /// [[T|alias]], ![[T]]. Behaviourally mirrors `WikilinkIndex`'s pattern
    /// (duplicated by design — the two files stay decoupled).
    private static let linkRegex = try! NSRegularExpression(
        pattern: #"!?\[\[([^\]\|#]+)(#[^\]\|]*)?(\|([^\]]+))?\]\]"#
    )

    /// Splits one line of text into text/wikilink runs. Empty input → `[]`.
    /// Empty-after-trim targets (`[[ ]]`) are left as plain text; zero-length text
    /// runs between adjacent links are dropped. Shared by heading/bullet/quote/paragraph.
    public static func runs(_ line: String) -> [InlineRun] {
        guard !line.isEmpty else { return [] }

        let ns = line as NSString
        var result: [InlineRun] = []
        var cursor = 0   // NSString index up to which output has been emitted

        // Emit any pending literal text in [cursor, upTo); drop zero-length spans.
        func emitText(upTo end: Int) {
            guard end > cursor else { return }
            result.append(.text(ns.substring(with: NSRange(location: cursor, length: end - cursor))))
        }

        for match in linkRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let target = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            // Empty-after-trim target isn't a real link: leave the raw match as text
            // (fold it into the pending literal span by not advancing the cursor).
            guard !target.isEmpty else { continue }

            emitText(upTo: match.range.location)

            let aliasRange = match.range(at: 4)
            let alias = aliasRange.location == NSNotFound
                ? nil
                : ns.substring(with: aliasRange).trimmingCharacters(in: .whitespaces)
            result.append(.wikilink(target: target, alias: alias))
            cursor = match.range.location + match.range.length
        }

        emitText(upTo: ns.length)
        return result
    }
}
