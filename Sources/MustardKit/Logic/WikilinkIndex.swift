import Foundation

/// Pure link-graph core for the Notes surface (design spec 2026-07-05, addendum #6).
/// Given a project's `[(relativePath, content)]`, parses frontmatter, extracts
/// `[[wikilinks]]`, resolves targets to paths, and builds the forward/backlink graph.
/// No filesystem, no clock, no SwiftData — so it stays unit-tested (CLAUDE.md rule).

/// One parsed note: frontmatter stripped, links extracted (not yet resolved).
public struct ParsedNote: Equatable {
    public let relativePath: String
    public let title: String          // frontmatter title ?? first "#{1,6} " heading ?? filename sans .md
    public let tags: [String]
    public let body: String           // content minus frontmatter block
    public let links: [WikilinkOccurrence]
}

public struct WikilinkOccurrence: Equatable {
    public let target: String         // "Note" from [[Note]], [[Note#H]], [[Note|alias]], ![[Note]]
    public let alias: String?
    public let line: String           // full containing line (backlink snippet context)
}

public struct Backlink: Hashable {
    public let sourcePath: String     // note containing the link
    public let snippet: String        // the containing line

    public init(sourcePath: String, snippet: String) {
        self.sourcePath = sourcePath
        self.snippet = snippet
    }
}

public struct WikilinkIndex: Equatable {
    public let notes: [ParsedNote]                    // sorted by relativePath
    public let forwardLinks: [String: [String]]       // path → resolved target paths (deduped, link order)
    public let backlinks: [String: [Backlink]]        // path → links into it (sorted by sourcePath)

    public static func build(_ docs: [(relativePath: String, content: String)]) -> WikilinkIndex {
        let notes = docs
            .map { parse(relativePath: $0.relativePath, content: $0.content) }
            .sorted { pathPrecedes($0.relativePath, $1.relativePath) }

        // Precompute lookup maps once so each occurrence resolves in O(1) — a
        // reindex touches every link in the project (O(links × N log N) otherwise).
        let maps = ResolutionMaps(paths: docs.map(\.relativePath))

        var forwardLinks: [String: [String]] = [:]
        var backlinkPairs: [String: [Backlink]] = [:]
        // Set membership keeps (target, source, snippet) dedupe linear;
        // backlinkPairs preserves insertion order for the final sort.
        var seenBacklinks: [String: Set<Backlink>] = [:]

        for note in notes {
            var seenTargets = Set<String>()
            var resolvedOrder: [String] = []
            for link in note.links {
                guard let resolved = resolve(target: link.target, using: maps) else { continue }
                if seenTargets.insert(resolved).inserted {
                    resolvedOrder.append(resolved)
                }
                let backlink = Backlink(sourcePath: note.relativePath, snippet: link.line)
                if seenBacklinks[resolved, default: []].insert(backlink).inserted {
                    backlinkPairs[resolved, default: []].append(backlink)
                }
            }
            if !resolvedOrder.isEmpty { forwardLinks[note.relativePath] = resolvedOrder }
        }

        let backlinks = backlinkPairs.mapValues { $0.sorted { pathPrecedes($0.sourcePath, $1.sourcePath) } }
        return WikilinkIndex(notes: notes, forwardLinks: forwardLinks, backlinks: backlinks)
    }

    /// Deterministic resolution (addendum #6): exact-path first for "/" targets, else
    /// case-insensitive filename match over candidates sorted by
    /// (path-component count, then lexicographic). nil if nothing matches.
    /// One-off convenience (e.g. resolving a clicked link); `build` shares the
    /// same semantics via precomputed `ResolutionMaps`.
    public static func resolve(target: String, in paths: [String]) -> String? {
        resolve(target: target, using: ResolutionMaps(paths: paths))
    }

    /// Same semantics as `resolve(target:in:)`, but the O(N log N) `ResolutionMaps`
    /// build happens ONCE — callers resolving many targets against one candidate set
    /// (e.g. every backlink row's snippet scan) hoist this instead of paying the
    /// rebuild per call.
    public static func resolver(paths: [String]) -> (String) -> String? {
        let maps = ResolutionMaps(paths: paths)
        return { resolve(target: $0, using: maps) }
    }

    /// Both priority rules folded into O(1)-lookup dictionaries, built in one pass each.
    private struct ResolutionMaps {
        /// lowercased extension-stripped full path → path (first in doc order wins).
        let exactByPath: [String: String]
        /// lowercased filename stem → winning path. First writer wins over
        /// candidates pre-sorted by (component count, lexicographic), preserving
        /// the "shortest path, then alphabetical" priority.
        let byStem: [String: String]

        init(paths: [String]) {
            var exact: [String: String] = [:]
            for path in paths {
                let key = stripExtension(path).lowercased()
                if exact[key] == nil { exact[key] = path }
            }
            exactByPath = exact

            var stems: [String: String] = [:]
            for path in sortedCandidates(paths) {
                let key = stripExtension((path as NSString).lastPathComponent).lowercased()
                if stems[key] == nil { stems[key] = path }
            }
            byStem = stems
        }
    }

    private static func resolve(target: String, using maps: ResolutionMaps) -> String? {
        let stripped = stripExtension(target)
        if stripped.contains("/"), let exact = maps.exactByPath[stripped.lowercased()] {
            return exact
        }
        // Fall through to filename matching against the last component.
        return maps.byStem[stripExtension((stripped as NSString).lastPathComponent).lowercased()]
    }

    // MARK: - Parsing

    private static func parse(relativePath: String, content: String) -> ParsedNote {
        let (fmTitle, tags, body) = Frontmatter.parse(content)
        let title = fmTitle ?? firstHeading(body) ?? filenameStem(relativePath)
        return ParsedNote(
            relativePath: relativePath,
            title: title,
            tags: tags,
            body: body,
            links: extractLinks(body)
        )
    }

    /// First heading of ANY level 1–6 (`#{1,6} `). Matches NoteEditorView's header
    /// scan (the forgiving choice) so a note starting `## Foo` titles as "Foo" in
    /// both the sidebar and the editor. Seven+ hashes or no trailing space is not a
    /// heading. Empty-after-hashes lines are skipped.
    private static func firstHeading(_ body: String) -> String? {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let hashes = line.prefix { $0 == "#" }.count
            guard hashes >= 1, hashes <= 6 else { continue }
            let rest = line.dropFirst(hashes)
            guard rest.hasPrefix(" ") else { continue }
            let title = rest.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
        }
        return nil
    }

    private static func filenameStem(_ relativePath: String) -> String {
        ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Wikilink grammar lives in `WikilinkSyntax` (one definition, three consumers);
    /// this layer adds only the fence rule: fenced lines (``` toggling) are skipped.
    private static func extractLinks(_ body: String) -> [WikilinkOccurrence] {
        var occurrences: [WikilinkOccurrence] = []
        var inFence = false
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }

            for occ in WikilinkSyntax.occurrences(in: line) {
                occurrences.append(WikilinkOccurrence(target: occ.target, alias: occ.alias, line: line))
            }
        }
        return occurrences
    }

    // MARK: - Resolution helpers

    /// Candidates sorted by (fewest path components, then lexicographic) — the
    /// "shortest-path wins" intuition from Obsidian (addendum #6).
    private static func sortedCandidates(_ paths: [String]) -> [String] {
        paths.sorted {
            let ca = $0.split(separator: "/").count, cb = $1.split(separator: "/").count
            return ca != cb ? ca < cb : pathPrecedes($0, $1)
        }
    }

    /// Case-insensitive lexicographic order — "a.md" before "Target.md", matching
    /// the user's alphabetical intuition rather than raw Unicode-scalar order.
    private static func pathPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.lowercased() < rhs.lowercased()
    }

    private static func stripExtension(_ path: String) -> String {
        (path as NSString).pathExtension.lowercased() == "md"
            ? (path as NSString).deletingPathExtension
            : path
    }
}

/// Minimal YAML frontmatter reader — only what Phase A needs (title, tags).
/// No general YAML parser (YAGNI); other keys are reserved for Phase B (e.g. `task_id`).
public enum Frontmatter {
    /// Detects a leading "---\n...\n---" block. Returns nil title/empty tags when absent.
    public static func parse(_ rawContent: String) -> (title: String?, tags: [String], body: String) {
        // Normalize Windows line endings ONCE at entry (BAK-71 hygiene): otherwise a
        // `---\r` fence line never equals "---" and frontmatter silently fails to
        // parse. Downstream consumers (WikilinkIndex.build, BacklinkSnippets) take the
        // body from here, so normalizing here covers their line handling too.
        let content = rawContent.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = content.components(separatedBy: "\n")
        guard lines.first == "---" else { return (nil, [], content) }

        // Find the closing "---" fence.
        guard let closeIndex = lines.dropFirst().firstIndex(of: "---") else {
            return (nil, [], content)   // unterminated — treat whole content as body
        }

        var title: String?
        var tags: [String] = []
        let frontLines = lines[1..<closeIndex]

        var index = frontLines.startIndex
        while index < frontLines.endIndex {
            let line = frontLines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let value = value(of: "title:", in: trimmed) {
                title = unquote(value)
            } else if let value = value(of: "tags:", in: trimmed) {
                if value.isEmpty {
                    // Block list: subsequent indented "- item" lines.
                    var cursor = frontLines.index(after: index)
                    while cursor < frontLines.endIndex {
                        let item = frontLines[cursor].trimmingCharacters(in: .whitespaces)
                        guard item.hasPrefix("- ") else { break }
                        tags.append(unquote(String(item.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                        cursor = frontLines.index(after: cursor)
                    }
                    index = cursor
                    continue
                } else {
                    tags = inlineTags(value)
                }
            }
            index = frontLines.index(after: index)
        }

        let body = lines[(closeIndex + 1)...].joined(separator: "\n")
        return (title, tags, body)
    }

    /// Returns the trimmed value after `key`, or nil if the line isn't that key.
    private static func value(of key: String, in line: String) -> String? {
        guard line.hasPrefix(key) else { return nil }
        return String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
    }

    /// `[a, b]` → ["a", "b"]. Bare (no brackets) is also tolerated.
    private static func inlineTags(_ value: String) -> [String] {
        var inner = value
        if inner.hasPrefix("[") { inner.removeFirst() }
        if inner.hasSuffix("]") { inner.removeLast() }
        return inner
            .split(separator: ",")
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    /// Strips one pair of surrounding single or double quotes.
    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        let first = value.first!, last = value.last!
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
