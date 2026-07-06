import Foundation

/// Pure decoration layer for the live Notes editor (Craft spec 2026-07-06, Phase 2a).
/// Maps markdown SOURCE → styled UTF-16 ranges + a total block partition. Read-only
/// by design: there is deliberately NO API that returns rewritten source — the
/// markdown-as-truth guarantee (spec hard constraint) is structural, not tested-in.
///
/// Operates on the RAW source string and never CRLF-normalizes — this layer must be
/// byte-faithful because its ranges index the exact string the text view holds
/// (text-view string == disk string). Contrast `MarkdownBlocks.parse`, which
/// normalizes because it only renders. All ranges are UTF-16 `NSRange`
/// (NSTextStorage coordinates), matching `WikilinkSyntax.Occurrence.range`.
public enum NoteDecoration {

    // MARK: - Blocks (total partition)

    public struct Block: Equatable {
        public let range: NSRange        // includes the block's trailing blank lines
        public let isFrontmatter: Bool   // leading --- YAML block (fences included)
        public let isFence: Bool         // ``` code block (fences included)

        public init(range: NSRange, isFrontmatter: Bool = false, isFence: Bool = false) {
            self.range = range
            self.isFrontmatter = isFrontmatter
            self.isFence = isFence
        }
    }

    /// Total partition of `source`: ranges are contiguous, in order, and cover every
    /// UTF-16 unit — substrings concatenated re-assemble the source EXACTLY.
    /// Grammar this editor doesn't understand (tables, setext, HTML) still lands in
    /// blocks (as paragraphs); nothing is dropped or normalized.
    ///
    /// Blocking mirrors `MarkdownBlocks.parse`'s line classification, but
    /// range-preserving: heading/rule/quote/list lines are one block per line,
    /// consecutive plain lines group into a paragraph, ``` fences swallow to the
    /// closing fence or EOF, and trailing blank lines attach to the preceding block
    /// (so blocks are the 2b drag units, separators included). Blank lines BEFORE
    /// the first block have no preceding block to join — they form one plain block
    /// of their own, keeping the partition total.
    public static func blocks(_ source: String) -> [Block] {
        let ns = source as NSString
        guard ns.length > 0 else { return [] }
        let all = lines(ns, in: NSRange(location: 0, length: ns.length))
        var blocks: [Block] = []
        var i = 0

        // Frontmatter: `Frontmatter.parse`'s detection rule applied to raw lines —
        // the FIRST line is exactly "---" and some later line closes it. Line
        // contents here already exclude the \n / \r\n terminator, so the raw
        // compare matches parse's normalize-then-compare without rewriting bytes.
        // Unterminated = not frontmatter; the opening "---" then reads as a rule.
        if all[0].content == "---",
           let close = all.dropFirst().firstIndex(where: { $0.content == "---" }) {
            var last = close
            while last + 1 < all.count, isBlank(all[last + 1]) { last += 1 }
            blocks.append(Block(range: NSRange(location: 0, length: all[last].range.upperBound),
                                isFrontmatter: true))
            i = last + 1
        }

        while i < all.count {
            let start = all[i].range.location
            var last = i
            var isFence = false

            switch classify(all[i].content) {
            case .blank:
                // Document-leading blank run (blanks after a block are absorbed
                // below and never reach the top of this loop).
                while last + 1 < all.count, isBlank(all[last + 1]) { last += 1 }
            case .fence:
                // Swallow to the closing fence or EOF — blank lines and would-be
                // markers inside stay inside, mirroring MarkdownBlocks' fence rule.
                isFence = true
                var j = i + 1
                while j < all.count, !isFenceLine(all[j]) { j += 1 }
                last = min(j, all.count - 1)
            case .text:
                // Consecutive plain lines group into one paragraph block.
                while last + 1 < all.count, case .text = classify(all[last + 1].content) { last += 1 }
            case .heading, .rule, .quote, .bullet, .ordered:
                break   // one block per line, exactly as MarkdownBlocks classifies
            }

            // Trailing blank lines attach to the block they follow.
            while last + 1 < all.count, isBlank(all[last + 1]) { last += 1 }

            blocks.append(Block(range: NSRange(location: start,
                                               length: all[last].range.upperBound - start),
                                isFence: isFence))
            i = last + 1
        }
        return blocks
    }

    // MARK: - Spans

    public struct Span: Equatable {
        public let range: NSRange
        public let kind: Kind

        public init(range: NSRange, kind: Kind) {
            self.range = range
            self.kind = kind
        }
    }

    public enum Kind: Equatable {
        case frontmatter                                  // whole YAML block incl. fences
        case heading(level: Int)                          // heading TEXT (hashes excluded)
        case marker                                       // syntax chars to de-emphasize
        case bold, italic, inlineCode                     // content between markers
        case codeBlock                                    // fence interior
        case listMarker                                   // "- " / "1. " / "> " prefix
        case wikilink(target: String, alias: String?)     // the VISIBLE label span
        /// A plain paragraph line whose ENTIRE trimmed content is one bare
        /// wikilink (`[[Target]]` alone on the line) — 2b renders it as a subpage
        /// card. Additive: the line keeps its normal wikilink/marker spans (the
        /// characters stay, the link stays clickable); this span only grounds the
        /// card drawing behind them. Deliberately tight: aliases, anchors, embeds,
        /// or any surrounding text stay ordinary wikilinks.
        case subpageCard(target: String)
    }

    /// All spans for the whole source.
    public static func spans(_ source: String) -> [Span] {
        blocks(source).flatMap { spans(source, in: $0) }
    }

    /// Spans for one block only — the per-keystroke fast path (2a coordinator).
    public static func spans(_ source: String, in block: Block) -> [Span] {
        let ns = source as NSString
        guard block.range.upperBound <= ns.length else { return [] }

        // Frontmatter: one quiet span over the whole block (fences and any trailing
        // blank lines included) — nothing inside YAML is parsed (plan Decision 3).
        if block.isFrontmatter {
            return [Span(range: block.range, kind: .frontmatter)]
        }

        let blockLines = lines(ns, in: block.range)
        if block.isFence {
            return fenceSpans(blockLines, blockEnd: block.range.upperBound)
        }
        return blockLines.flatMap { lineSpans($0) }
    }

    // MARK: - Per-kind span builders

    /// Fence lines de-emphasize as `.marker` (language tag included); the interior —
    /// everything between them, newlines and all — is one `.codeBlock` span with NO
    /// inline/wikilink spans inside (matches `WikilinkIndex.extractLinks`' fence
    /// rule). An unterminated fence swallows to the block end.
    private static func fenceSpans(_ blockLines: [Line], blockEnd: Int) -> [Span] {
        guard let open = blockLines.first else { return [] }
        var spans = [Span(range: open.contentRange, kind: .marker)]

        let closeIndex = blockLines.indices.dropFirst().last(where: { isFenceLine(blockLines[$0]) })
        let interiorStart = open.range.upperBound
        let interiorEnd = closeIndex.map { blockLines[$0].range.location } ?? blockEnd
        if interiorEnd > interiorStart {
            spans.append(Span(range: NSRange(location: interiorStart,
                                             length: interiorEnd - interiorStart),
                              kind: .codeBlock))
        }
        if let closeIndex {
            spans.append(Span(range: blockLines[closeIndex].contentRange, kind: .marker))
        }
        return spans
    }

    /// Spans for one line of a normal (non-frontmatter, non-fence) block: a line
    /// prefix span per the line's class, then the shared inline scanner over the
    /// rest. A rule line is pure syntax — the whole line de-emphasizes as `.marker`.
    private static func lineSpans(_ line: Line) -> [Span] {
        let content = line.content
        let contentNS = content as NSString
        let base = line.contentRange.location

        switch classify(content) {
        case .blank:
            return []

        case .rule:
            return [Span(range: line.contentRange, kind: .marker)]

        case .heading(let level):
            // "#…# " prefix (leading indent included) is marker; the rest is the
            // heading text, which still gets inline spans (bold/links in headings).
            let prefix = leadingWhitespaceCount(content) + level + 1
            var spans = [Span(range: NSRange(location: base, length: prefix), kind: .marker)]
            let textLength = contentNS.length - prefix
            if textLength > 0 {
                spans.append(Span(range: NSRange(location: base + prefix, length: textLength),
                                  kind: .heading(level: level)))
                spans += inlineSpans(in: contentNS.substring(from: prefix), at: base + prefix)
            }
            return spans

        case .quote:
            return prefixedLineSpans(content, base: base,
                                     prefix: leadingWhitespaceCount(content) + 2)

        case .bullet:
            // Indent measured in raw leading SPACES, mirroring MarkdownBlocks.
            return prefixedLineSpans(content, base: base,
                                     prefix: leadingSpaceCount(content) + 2)

        case .ordered:
            let spaces = leadingSpaceCount(content)
            let digits = content.dropFirst(spaces).prefix { $0.isNumber }.count
            return prefixedLineSpans(content, base: base, prefix: spaces + digits + 2)

        case .text:
            var spans = inlineSpans(in: content, at: base)
            if let target = subpageCardTarget(content) {
                // Card span covers the line's content range (whitespace included)
                // so the drawn card grounds the whole line, not just the glyphs.
                spans.append(Span(range: line.contentRange, kind: .subpageCard(target: target)))
            }
            return spans

        case .fence:
            // A fence line inside a normal block can't happen (it opens its own
            // block); defensive raw.
            return []
        }
    }

    /// "- " / "1. " / "> " prefix (leading indent included) as `.listMarker`, then
    /// inline spans over the rest of the line.
    private static func prefixedLineSpans(_ content: String, base: Int, prefix: Int) -> [Span] {
        let contentNS = content as NSString
        var spans = [Span(range: NSRange(location: base, length: prefix), kind: .listMarker)]
        if contentNS.length > prefix {
            spans += inlineSpans(in: contentNS.substring(from: prefix), at: base + prefix)
        }
        return spans
    }

    // MARK: - Inline scanner (shared by heading/list/quote/paragraph lines)

    /// Deliberately tight inline grammar (anything else stays raw text): code spans
    /// first (opaque — no emphasis and no wikilinks inside, the fence rule one level
    /// down), then wikilinks (the ONE grammar: `WikilinkSyntax.regex`, group ranges
    /// read directly so markers/label split without re-deriving the pattern), then
    /// `**bold**`, then `*italic*`. Single-line, non-nested; underscore emphasis is
    /// NOT parsed. Lookarounds on the emphasis patterns keep unmatched runs ("**a",
    /// "***x***") raw rather than guessed. A claimed-mask enforces first-wins.
    private static let codeSpanRegex = try! NSRegularExpression(pattern: "`([^`]+)`")
    private static let boldRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*\*([^*]+)\*\*(?!\*)"#)
    private static let italicRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#)

    private static func inlineSpans(in text: String, at base: Int) -> [Span] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }
        let full = NSRange(location: 0, length: ns.length)
        var claimed = [Bool](repeating: false, count: ns.length)
        var spans: [Span] = []

        func isFree(_ r: NSRange) -> Bool {
            !(r.lowerBound..<r.upperBound).contains { claimed[$0] }
        }
        func claim(_ r: NSRange) {
            for k in r.lowerBound..<r.upperBound { claimed[k] = true }
        }
        func add(_ r: NSRange, _ kind: Kind) {
            guard r.length > 0 else { return }
            spans.append(Span(range: NSRange(location: base + r.location, length: r.length),
                              kind: kind))
        }

        for m in codeSpanRegex.matches(in: text, range: full) where isFree(m.range) {
            add(NSRange(location: m.range.location, length: 1), .marker)
            add(m.range(at: 1), .inlineCode)
            add(NSRange(location: m.range.upperBound - 1, length: 1), .marker)
            claim(m.range)
        }

        for m in WikilinkSyntax.regex.matches(in: text, range: full) where isFree(m.range) {
            let targetRange = m.range(at: 1)
            let target = ns.substring(with: targetRange).trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { continue }   // "[[ ]]" is not a link (WikilinkSyntax rule)
            let anchorRange = m.range(at: 2)
            let aliasRange = m.range(at: 4)

            // Leading "[[" (or "![[" for embeds).
            add(NSRange(location: m.range.location,
                        length: targetRange.location - m.range.location), .marker)
            if aliasRange.location != NSNotFound {
                // Aliased: target half, any #anchor, and the "|" all de-emphasize;
                // the alias is the visible label.
                let alias = ns.substring(with: aliasRange).trimmingCharacters(in: .whitespaces)
                add(NSRange(location: targetRange.location,
                            length: aliasRange.location - targetRange.location), .marker)
                add(aliasRange, .wikilink(target: target, alias: alias))
                add(NSRange(location: aliasRange.upperBound,
                            length: m.range.upperBound - aliasRange.upperBound), .marker)
            } else {
                add(targetRange, .wikilink(target: target, alias: nil))
                if anchorRange.location != NSNotFound { add(anchorRange, .marker) }
                let labelEnd = anchorRange.location != NSNotFound
                    ? anchorRange.upperBound : targetRange.upperBound
                add(NSRange(location: labelEnd, length: m.range.upperBound - labelEnd), .marker)
            }
            claim(m.range)
        }

        for m in boldRegex.matches(in: text, range: full) where isFree(m.range) {
            add(NSRange(location: m.range.location, length: 2), .marker)
            add(m.range(at: 1), .bold)
            add(NSRange(location: m.range.upperBound - 2, length: 2), .marker)
            claim(m.range)
        }

        for m in italicRegex.matches(in: text, range: full) where isFree(m.range) {
            add(NSRange(location: m.range.location, length: 1), .marker)
            add(m.range(at: 1), .italic)
            add(NSRange(location: m.range.upperBound - 1, length: 1), .marker)
            claim(m.range)
        }

        return spans
    }

    /// The subpage-card shape (2b, deliberately tight): the trimmed line is
    /// exactly `[[Target]]` — no alias, no `#anchor`, no `![[embed]]`, no
    /// surrounding text, and the target carries no stray brackets/pipes and no
    /// edge whitespace (`[[ T ]]`'s raw inner " T " differs from the trimmed
    /// target WikilinkSyntax/resolvers use, so it stays an ordinary link rather
    /// than a card with a mismatched title). Anything looser renders as a normal
    /// wikilink.
    private static func subpageCardTarget(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]") else { return nil }
        let target = String(trimmed.dropFirst(2).dropLast(2))
        guard !target.isEmpty,
              !target.contains("["), !target.contains("]"),
              !target.contains("|"), !target.contains("#"),
              target == target.trimmingCharacters(in: .whitespaces)
        else { return nil }
        return target
    }

    // MARK: - Line scanning + classification

    /// One raw line: `range` includes the terminator (\n, \r, or \r\n — kept with
    /// the owning line so the partition never splits a CRLF pair), `contentRange`
    /// and `content` exclude it.
    private struct Line {
        let range: NSRange
        let contentRange: NSRange
        let content: String
    }

    /// Line ranges via `getLineStart` (never `components(separatedBy:)`, which
    /// loses \r\n fidelity). A trailing newline belongs to the last line's range,
    /// so no phantom empty line is produced after it.
    private static func lines(_ ns: NSString, in range: NSRange) -> [Line] {
        var result: [Line] = []
        var location = range.location
        let limit = range.upperBound
        while location < limit {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                            for: NSRange(location: location, length: 0))
            let contentRange = NSRange(location: start, length: contentsEnd - start)
            result.append(Line(range: NSRange(location: start, length: end - start),
                               contentRange: contentRange,
                               content: ns.substring(with: contentRange)))
            location = end
        }
        return result
    }

    private enum LineKind {
        case blank, fence, rule, quote, bullet, ordered, text
        case heading(Int)
    }

    /// Same predicates as `MarkdownBlocks.blockLine`, same order (rule before
    /// heading; fence before everything non-blank).
    private static func classify(_ content: String) -> LineKind {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .blank }
        if trimmed.hasPrefix("```") { return .fence }
        if trimmed == "---" || trimmed == "***" { return .rule }
        if let level = headingLevel(trimmed) { return .heading(level) }
        if trimmed.hasPrefix("> ") { return .quote }
        let afterIndent = content.drop { $0 == " " }
        if afterIndent.hasPrefix("- ") || afterIndent.hasPrefix("* ") { return .bullet }
        if isOrdered(afterIndent) { return .ordered }
        return .text
    }

    /// `#{1,6} ` → the level; seven hashes or no trailing space is not a heading.
    private static func headingLevel(_ trimmed: String) -> Int? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard hashes >= 1, hashes <= 6, trimmed.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return hashes
    }

    /// `\d+. ` — only the dot form, matching MarkdownBlocks' light scope.
    private static func isOrdered(_ afterIndent: Substring) -> Bool {
        let digits = afterIndent.prefix { $0.isNumber }.count
        return digits >= 1 && afterIndent.dropFirst(digits).hasPrefix(". ")
    }

    private static func isBlank(_ line: Line) -> Bool {
        line.content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isFenceLine(_ line: Line) -> Bool {
        line.content.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    /// All whitespace characters are single UTF-16 units, so a Character count is
    /// a valid UTF-16 offset here.
    private static func leadingWhitespaceCount(_ content: String) -> Int {
        content.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func leadingSpaceCount(_ content: String) -> Int {
        content.prefix { $0 == " " }.count
    }
}
