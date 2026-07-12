import Foundation

/// Pure "turn into" + block-actions splices for the live editor (Craft spec,
/// Phase 3 / BAK-252, epic BAK-248). Four operations, each `(source, block) ->
/// (newSource, selection)?`, mirroring `BlockReorder.move`'s "the ONLY function
/// that rewrites note source for X" pattern one level up: `BlockTransform` owns
/// retype/duplicate/delete, `BlockReorder` still owns pure reorder (moveUp/
/// moveDown delegate into it rather than reimplementing index math).
///
/// Every function returns `nil` for a frontmatter block — the leading YAML
/// block has no menu (task.md / spec: "Frontmatter blocks: no menu, they're not
/// content blocks") — and for an out-of-bounds `block` (stale range from a
/// caller holding an old partition). Every other content block always succeeds:
/// even a "lossy" `turnInto` (e.g. table → heading) falls back to the block's
/// plain-text content rather than returning `nil`, per the spec's "never
/// corrupt the file, not never lose formatting" contract.
public enum BlockTransform {

    // MARK: - Turn into

    /// The only targets the "Turn into" menu offers (task.md item 1): Paragraph,
    /// Heading 1-4, Quote, Bullet/Numbered/Check List, Code Block. `turnInto`
    /// rejects any other `target` (`.divider`, `.table`, `.image`, `.subpage`)
    /// with `nil` — none of them has a well-defined "build this FROM arbitrary
    /// text" shape (divider is content-free; table/image/subpage are structured
    /// atoms, not typed-in prose), so there is no sensible menu entry for them
    /// as a destination. They remain valid as a SOURCE kind (see `turnInto`'s doc).
    public static let menuTargets: [BlockKind] = [
        .paragraph, .heading(1), .heading(2), .heading(3), .heading(4),
        .quote, .bulletList, .numberedList, .todoList, .codeBlock
    ]

    /// Converts `block`'s markdown to `target`'s shape, preserving text content
    /// wherever the two kinds are structurally compatible, never emitting
    /// malformed markdown otherwise (spec "Failure / edge behaviour").
    ///
    /// **Source-kind handling (every `BlockKind` `NoteDecoration.blockKind` can
    /// return, except frontmatter which is excluded above the switch):**
    /// - `.paragraph` — one content line per raw line (a multi-line paragraph
    ///   stays multi-line; see "Multi-line blocks" below).
    /// - `.heading`/`.quote`/`.bulletList`/`.numberedList`/`.todoList` — always
    ///   exactly ONE content line (`NoteDecoration.blocks` partitions these one
    ///   line per block already), prefix stripped per kind (checkbox marker
    ///   additionally stripped for `.todoList`).
    /// - `.codeBlock` — the fence's INTERIOR lines (opening/closing delimiters
    ///   excluded; an unterminated fence's interior runs to the block end,
    ///   mirroring `NoteDecoration.blocks`' own fence rule). Genuinely
    ///   multi-line; see below.
    /// - `.table` — **lossy fallback**: each non-separator row's cells (pipes
    ///   and dashed separator rows dropped) joined by a single space, one
    ///   content line per data row — plain-text content, per the spec
    ///   fallback. Deliberately NOT the raw `| a | b |` bytes: keeping the
    ///   pipes verbatim would round-trip right back to `.table` when the
    ///   target is `.paragraph` (a "|"-bearing multi-row block with a
    ///   separator row re-classifies as a table regardless of what put it
    ///   there — `NoteDecoration.blockKind`'s rule, not this file's), which
    ///   would silently defeat the very conversion the user asked for.
    /// - `.image`/`.subpage` — **atomic, not content-free, but not the raw
    ///   markdown either**: the meaningful text is the alt text (`![alt](url)`
    ///   → `alt`) or the link title (`[[Target]]` → `Target`) — same
    ///   reasoning as `.table`: re-emitting the exact original bracket/paren
    ///   syntax under a `.paragraph` target would satisfy `isImageLine`/
    ///   `subpageCardTarget` again and round-trip back to `.image`/`.subpage`
    ///   instead of `.paragraph`. Extracting the human-readable text avoids
    ///   that AND is the more honest reading of "plain-text content" for an
    ///   image/link atom.
    /// - `.divider` — **content-free, excluded as a source**: returns `nil`
    ///   rather than manufacture an empty/misleading heading or list item from
    ///   nothing. The "Turn into" menu should not be offered at all for a
    ///   divider block (view-layer decision, documented at the call site).
    ///
    /// **Multi-line blocks (paragraph, code block):** every content line is
    /// rendered independently through `target`'s per-line marker EXCEPT
    /// `.codeBlock`, which wraps ALL content lines together in one fence
    /// (fences added/removed, inner content untouched) rather than fencing each
    /// line separately. So e.g. a 3-line quote-shaped source can't exist (quote
    /// is one-line-per-block), but a 3-line PARAGRAPH → `.bulletList` produces
    /// THREE separate bullet lines (three re-partitioned blocks on the next
    /// parse) — "quote→bullet converts each line", generalized to every
    /// per-line target kind.
    ///
    /// **Newline normalization (documented simplification):** rendered content
    /// always ends each line with "\n", even when the original block's last
    /// line lacked a terminator (EOF). Unlike `BlockReorder.move`, `turnInto`
    /// can change the number of output lines (line-per-item explosion), so
    /// "preserve the one missing final terminator" doesn't generalize cleanly —
    /// adding a trailing newline at EOF is harmless, never corruption. The
    /// block's trailing blank-line TAIL (the separator rhythm after it) is
    /// preserved byte-verbatim via the same split `BlockReorder` uses.
    ///
    /// Selection lands just after `target`'s first rendered line's prefix
    /// (e.g. right after "## " for a heading) — inside the transformed block,
    /// at the natural typing position.
    public static func turnInto(_ source: String, block: NoteDecoration.Block, target: BlockKind) -> (source: String, selection: NSRange)? {
        guard !block.isFrontmatter, isInBounds(block, of: source) else { return nil }
        guard menuTargets.contains(target) else { return nil }
        guard let currentKind = NoteDecoration.blockKind(source, of: block), currentKind != .divider else { return nil }

        let ns = source as NSString
        let slice = ns.substring(with: block.range)
        let (content, tail) = BlockReorder.splitTrailingBlanks(slice)
        let contentLines = extractContentLines(content, kind: currentKind)
        let (rendered, caretOffset) = renderLines(contentLines, target: target)

        let newBlockText = rendered + tail
        let newSource = ns.replacingCharacters(in: block.range, with: newBlockText)
        let selection = NSRange(location: block.range.location + caretOffset, length: 0)
        return (newSource, selection)
    }

    // MARK: - Actions: Duplicate / Delete

    /// Duplicates `block` in place: the whole range (content + trailing blank
    /// tail) is replaced by two back-to-back copies of itself, so the tail's
    /// blank-line rhythm reappears after EACH copy (`"para\n\n"` duplicates to
    /// `"para\n\npara\n\n"`, not `"para\npara\n\n"`). The one hygiene byte: an
    /// EOF block with no trailing terminator at all gains a "\n" between the
    /// two copies so they can't fuse into one line (same rule
    /// `BlockReorder.move` applies to a displaced EOF block).
    ///
    /// Selection lands at the start of the NEW (second) copy — Duplicate is a
    /// "make a sibling and go there" action, mirroring the Notion/Craft
    /// convention this menu is modeled on.
    public static func duplicate(_ source: String, block: NoteDecoration.Block) -> (source: String, selection: NSRange)? {
        guard !block.isFrontmatter, isInBounds(block, of: source), block.range.length > 0 else { return nil }
        let ns = source as NSString
        let slice = ns.substring(with: block.range)

        var firstCopy = slice
        if let last = slice.unicodeScalars.last, last != "\n", last != "\r" {
            firstCopy += "\n"
        }
        let replacement = firstCopy + slice
        let newSource = ns.replacingCharacters(in: block.range, with: replacement)
        let selection = NSRange(location: block.range.location + (firstCopy as NSString).length, length: 0)
        return (newSource, selection)
    }

    /// Deletes `block` outright (its full range, tail included, removed with no
    /// replacement). Selection collapses to `block.range.location` — because
    /// `NoteDecoration.blocks` is a CONTIGUOUS total partition, the block
    /// immediately before and the text immediately after both already sit at
    /// that exact offset, so "start of the next block" and "end of the
    /// previous block" (the spec's two EOF-vs-not cases) are the same number;
    /// no branch needed. Clamped to the new (shorter) document length for the
    /// all-blocks-deleted edge.
    public static func delete(_ source: String, block: NoteDecoration.Block) -> (source: String, selection: NSRange)? {
        guard !block.isFrontmatter, isInBounds(block, of: source) else { return nil }
        let ns = source as NSString
        let newSource = ns.replacingCharacters(in: block.range, with: "")
        let newLength = (newSource as NSString).length
        let location = min(block.range.location, newLength)
        return (newSource, NSRange(location: location, length: 0))
    }

    // MARK: - Actions: Move up / down

    /// One slot earlier among moveable (non-frontmatter) blocks. `nil` when
    /// `block` is already first (nothing to swap with) — the menu item should
    /// disable rather than silently no-op (view-layer decision).
    public static func moveUp(_ source: String, block: NoteDecoration.Block) -> (source: String, selection: NSRange)? {
        move(source, block: block, delta: -1)
    }

    /// One slot later among moveable (non-frontmatter) blocks. `nil` when
    /// `block` is already last.
    public static func moveDown(_ source: String, block: NoteDecoration.Block) -> (source: String, selection: NSRange)? {
        move(source, block: block, delta: 1)
    }

    /// Shared move: delegates the actual splice to `BlockReorder.move` (index
    /// math, separator hygiene, frontmatter skip — all already correct and
    /// byte-pinned in `BlockReorderTests`; not reimplemented here). This layer
    /// only (a) turns `block` into the moveable index `BlockReorder.move`
    /// wants, and (b) re-derives the moved block's NEW range afterward so the
    /// caret can follow it — `move` itself returns only the spliced string.
    private static func move(_ source: String, block: NoteDecoration.Block, delta: Int) -> (source: String, selection: NSRange)? {
        guard !block.isFrontmatter, isInBounds(block, of: source) else { return nil }
        let moveable = NoteDecoration.blocks(source).filter { !$0.isFrontmatter }
        guard let index = moveable.firstIndex(where: { $0.range == block.range }) else { return nil }
        let target = index + delta
        guard target >= 0, target < moveable.count else { return nil }

        let newSource = BlockReorder.move(source, from: index, to: target)
        guard newSource != source else { return nil }
        let newMoveable = NoteDecoration.blocks(newSource).filter { !$0.isFrontmatter }
        guard target < newMoveable.count else { return nil }
        let selection = NSRange(location: newMoveable[target].range.location, length: 0)
        return (newSource, selection)
    }

    // MARK: - Content line extraction (source side)

    private static func isInBounds(_ block: NoteDecoration.Block, of source: String) -> Bool {
        block.range.location >= 0 && block.range.upperBound <= (source as NSString).length
    }

    /// Splits raw text into lines via `getLineStart` (never
    /// `components(separatedBy:)`, which would lose CRLF fidelity) — same idiom
    /// `NoteDecoration`/`BlockReorder` use. Terminators are dropped: rendering
    /// always rejoins with "\n" (see `turnInto`'s newline-normalization note).
    private static func rawLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        var result: [String] = []
        var location = 0
        while location < ns.length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            result.append(ns.substring(with: NSRange(location: start, length: contentsEnd - start)))
            location = end
        }
        return result
    }

    /// `content`'s lines, source-kind prefix stripped — the plain text `turnInto`
    /// re-renders under `target`'s prefix. One entry per case in `BlockKind`
    /// (see `turnInto`'s doc for the reasoning behind each).
    private static func extractContentLines(_ content: String, kind: BlockKind) -> [String] {
        let raw = rawLines(content)
        switch kind {
        case .paragraph:
            return raw
        case .heading(let level):
            return raw.map { stripHeadingPrefix($0, level: level) }
        case .quote:
            return raw.map { stripQuotePrefix($0) }
        case .bulletList:
            return raw.map { stripListPrefix($0) }
        case .todoList:
            return raw.map { stripTodoMarker(stripListPrefix($0)) }
        case .numberedList:
            return raw.map { stripOrderedPrefix($0) }
        case .codeBlock:
            return fenceInterior(raw)
        case .table:
            return tablePlainTextRows(raw)
        case .image:
            return [imageAltText(raw.first ?? "")]
        case .subpage:
            return [subpageTitleText(raw.first ?? "")]
        case .divider:
            return []   // unreachable — turnInto excludes divider sources earlier
        }
    }

    /// `![alt](url)` → `alt` (empty string if there's no alt text). Falls back
    /// to the raw trimmed line if it somehow doesn't match the image shape
    /// (defensive — `blockKind` already confirmed `.image` before this runs).
    private static let imageAltRegex = try! NSRegularExpression(pattern: #"^!\[([^\]]*)\]\([^)]*\)$"#)
    private static func imageAltText(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let ns = trimmed as NSString
        guard let match = imageAltRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length))
        else { return trimmed }
        return ns.substring(with: match.range(at: 1))
    }

    /// `[[Target]]` → `Target`. Defensive fallback to the raw trimmed line,
    /// same reasoning as `imageAltText`.
    private static func subpageTitleText(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]") else { return trimmed }
        return String(trimmed.dropFirst(2).dropLast(2))
    }

    /// One content line per DATA row (separator rows like `|---|---|` carry no
    /// content and are dropped entirely): pipes stripped, cells trimmed and
    /// joined with a single space. Mirrors `NoteDecoration.isTableSeparatorRow`'s
    /// separator-detection rule (not reused directly — that helper is private
    /// to `NoteDecoration` — but the same "every cell is only `-`/`:`" shape).
    private static func tablePlainTextRows(_ raw: [String]) -> [String] {
        var result: [String] = []
        for line in raw {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !isTableSeparatorRow(trimmed) else { continue }
            result.append(tableCells(trimmed).joined(separator: " "))
        }
        return result
    }

    private static func tableCells(_ trimmedRow: String) -> [String] {
        var cells = trimmedRow.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells
    }

    private static func isTableSeparatorRow(_ trimmedRow: String) -> Bool {
        let cells = tableCells(trimmedRow)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            !cell.isEmpty && cell.contains("-") && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    /// Fence interior: opening delimiter always dropped; the LAST line drops
    /// too as the closing delimiter IFF there's more than one line and it's a
    /// fence line itself — otherwise (a single-line or unterminated fence) it
    /// stays interior, mirroring `NoteDecoration.blocks`' "swallow to the
    /// closing fence or EOF" rule.
    private static func fenceInterior(_ raw: [String]) -> [String] {
        guard raw.count > 1 else { return [] }
        var lines = Array(raw.dropFirst())
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeLast()
        }
        return lines
    }

    private static func stripHeadingPrefix(_ line: String, level: Int) -> String {
        let ns = line as NSString
        let leadingWS = line.prefix { $0 == " " || $0 == "\t" }.count
        let prefixLen = leadingWS + level + 1
        guard ns.length >= prefixLen else { return "" }
        return ns.substring(from: prefixLen)
    }

    private static func stripQuotePrefix(_ line: String) -> String {
        let ns = line as NSString
        let leadingWS = line.prefix { $0 == " " || $0 == "\t" }.count
        let prefixLen = leadingWS + 2
        guard ns.length >= prefixLen else { return "" }
        return ns.substring(from: prefixLen)
    }

    /// "- "/"* " prefix stripped (leading spaces measured in raw SPACES, matching
    /// `NoteDecoration.lineSpans`' bullet case — tabs don't count here).
    private static func stripListPrefix(_ line: String) -> String {
        let ns = line as NSString
        let leadingSpaces = line.prefix { $0 == " " }.count
        let afterIndent = ns.substring(from: min(leadingSpaces, ns.length))
        if afterIndent.hasPrefix("- ") || afterIndent.hasPrefix("* ") {
            return String(afterIndent.dropFirst(2))
        }
        return line
    }

    /// The checkbox marker after a bullet prefix is already stripped
    /// (`"[ ] rest"`, `"[x]"` bare, etc.) — mirrors `NoteDecoration.isTodoLine`'s
    /// three recognized marks.
    private static func stripTodoMarker(_ text: String) -> String {
        for marker in ["[ ]", "[x]", "[X]"] {
            if text == marker { return "" }
            if text.hasPrefix(marker + " ") { return String(text.dropFirst(marker.count + 1)) }
        }
        return text
    }

    /// "1. " prefix stripped (matching `NoteDecoration.lineSpans`' ordered case:
    /// leading spaces, then digits, then ". ").
    private static func stripOrderedPrefix(_ line: String) -> String {
        let leadingSpaces = line.prefix { $0 == " " }.count
        let afterSpaces = line.dropFirst(leadingSpaces)
        let digits = afterSpaces.prefix { $0.isNumber }.count
        guard digits > 0 else { return line }
        let rest = afterSpaces.dropFirst(digits)
        guard rest.hasPrefix(". ") else { return line }
        return String(rest.dropFirst(2))
    }

    // MARK: - Rendering (target side)

    /// Renders `lines` (already source-prefix-stripped) under `target`'s
    /// marker. Returns the rendered text (every line "\n"-terminated) and the
    /// caret offset from the block's start — right after the FIRST rendered
    /// line's prefix, e.g. offset 3 for `.heading(2)` ("## ").
    private static func renderLines(_ lines: [String], target: BlockKind) -> (text: String, caretOffset: Int) {
        let contentLines = lines.isEmpty ? [""] : lines
        switch target {
        case .paragraph:
            return (contentLines.map { $0 + "\n" }.joined(), 0)
        case .heading(let rawLevel):
            let level = min(max(rawLevel, 1), 6)
            let prefix = String(repeating: "#", count: level) + " "
            return (contentLines.map { prefix + $0 + "\n" }.joined(), (prefix as NSString).length)
        case .quote:
            return (contentLines.map { "> " + $0 + "\n" }.joined(), 2)
        case .bulletList:
            return (contentLines.map { "- " + $0 + "\n" }.joined(), 2)
        case .todoList:
            return (contentLines.map { "- [ ] " + $0 + "\n" }.joined(), 6)
        case .numberedList:
            var text = ""
            for (offset, line) in contentLines.enumerated() {
                text += "\(offset + 1). " + line + "\n"
            }
            return (text, ("1. " as NSString).length)
        case .codeBlock:
            let text = "```\n" + contentLines.joined(separator: "\n") + "\n```\n"
            return (text, ("```\n" as NSString).length)
        case .divider, .table, .image, .subpage:
            // Unreachable in practice — `turnInto` only calls this after
            // `menuTargets.contains(target)`, which excludes these four. Kept
            // exhaustive (no `default:`) so a future `BlockKind` case forces a
            // decision here rather than silently falling through.
            return (contentLines.map { $0 + "\n" }.joined(), 0)
        }
    }
}
