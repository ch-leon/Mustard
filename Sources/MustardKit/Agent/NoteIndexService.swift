import Foundation
import SwiftData
import Observation

/// Rebuilds the per-project NoteIndexEntry mirror from the vault (BAK-148). Pure
/// filesystem work — no claude, no cost — so it can run every few minutes plus
/// immediately after an editor save. Wholesale rebuild per project (spec: vaults
/// are hundreds of files; avoids stale-edge bugs from incremental patching).
@MainActor
@Observable
public final class NoteIndexService {
    /// Bump whenever parsing or derivation changes ship (title rules, CRLF
    /// normalization, link grammar). CONSTRAINT: the change-guard compares only
    /// (path, mtime) — a parser change alters DERIVED rows without touching bytes
    /// on disk, so without this salt a shipped fix (e.g. this PR's any-heading
    /// title + CRLF fixes) would never reach already-indexed notes. A stored-vs-
    /// code mismatch disables the guard for the whole session (every project
    /// rebuilds within the first loop tick) and writes the new version
    /// immediately, so the next launch trusts the guard again.
    public static let parserVersion = 2
    private static let parserVersionKey = "noteIndexParserVersion"

    public private(set) var isIndexing = false
    public private(set) var lastIndexedAt: [String: Date] = [:]   // project → time (in-memory throttle)

    private let context: ModelContext
    private let makeIO: (String) -> NoteVaultIO
    /// True when the on-disk index predates the current parser (see parserVersion).
    private let guardDisabledThisSession: Bool

    public init(context: ModelContext,
                makeIO: @escaping (String) -> NoteVaultIO = { FileVaultIO(rootPath: $0) },
                defaults: UserDefaults = .standard) {
        self.context = context
        self.makeIO = makeIO
        guardDisabledThisSession = defaults.integer(forKey: Self.parserVersionKey) != Self.parserVersion
        if guardDisabledThisSession {
            defaults.set(Self.parserVersion, forKey: Self.parserVersionKey)
        }
    }

    /// 60s-loop entry point: reindex every enabled project whose throttle has lapsed.
    public func reindexDueProjects(_ settings: SourceSettings, now: Date = .now) {
        for config in settings.sources where config.enabled && !config.workingDirectory.isEmpty {
            guard NoteReindexScheduler.isDue(lastIndexedAt: lastIndexedAt[config.project], now: now) else { continue }
            reindex(project: config.project, workingDirectory: config.workingDirectory, now: now)
        }
    }

    /// Manual "Reindex notes now" (⌘K): every enabled project, throttle ignored —
    /// and forced past the change-guard: the user's explicit ask must always
    /// rebuild, even when disk looks untouched.
    public func reindexAll(_ settings: SourceSettings, now: Date = .now) {
        for config in settings.sources where config.enabled && !config.workingDirectory.isEmpty {
            reindex(project: config.project, workingDirectory: config.workingDirectory, now: now, force: true)
        }
    }

    /// Wholesale rebuild of one project's entries. Also the on-save hook.
    /// `force: true` (the manual ⌘K path) bypasses the change-guard entirely.
    public func reindex(project: String, workingDirectory: String, now: Date = .now, force: Bool = false) {
        isIndexing = true
        defer { isIndexing = false }
        let io = makeIO(workingDirectory)
        // Project-scoped fetch: rows carry full contentSnapshots, so materializing
        // every project's rows just to delete one project's is real churn.
        let descriptor = FetchDescriptor<NoteIndexEntry>(predicate: #Predicate { $0.project == project })
        // If the fetch throws, bail out of the whole rebuild — no inserts, no
        // lastIndexedAt advance. Inserting without deleting would leave stale rows
        // alongside the new ones as duplicate (project, relativePath) rows with no
        // unique constraint to stop them; a skipped cycle just retries next tick.
        guard let existing = try? context.fetch(descriptor) else { return }

        // Stat BEFORE read (TOCTOU): these mtimes feed both the change-guard and
        // the stored lastModified below. If a write lands between this stat and the
        // content read, we store the PRE-write mtime alongside the post-write
        // content, so next tick disk ≠ stored → rebuild (the safe direction).
        // Re-statting after the reads could stamp a NEWER mtime than the content
        // actually read and make the guard skip that racing write forever.
        let diskPaths = io.notePaths()
        let disk = diskPaths.map { (path: $0, modified: io.modificationDate($0)) }

        // Cheap change-guard (BAK-71 hygiene): if the disk path SET and every
        // (path, mtime) pair already match the stored index, skip the delete+reinsert
        // entirely — just advance the throttle. Avoids disk churn now and CloudKit
        // sync traffic when N2 lands. Consulted only when not forced and the
        // parser-version salt didn't invalidate the index this session.
        if !force && !guardDisabledThisSession {
            let indexed = existing.map { (path: $0.relativePath, modified: $0.lastModified) }
            if NoteReindexScheduler.isUnchanged(disk: disk, indexed: indexed) {
                lastIndexedAt[project] = now
                return
            }
        }

        let docs = diskPaths.compactMap { path -> (relativePath: String, content: String)? in
            io.read(path).map { (path, $0) }
        }
        let index = WikilinkIndex.build(docs)
        for entry in existing { context.delete(entry) }
        let contentByPath = Dictionary(docs.map { ($0.relativePath, $0.content) }, uniquingKeysWith: { a, _ in a })
        let mtimeByPath = Dictionary(disk.map { ($0.path, $0.modified) }, uniquingKeysWith: { a, _ in a })
        for note in index.notes {
            context.insert(NoteIndexEntry(
                project: project, relativePath: note.relativePath, title: note.title,
                tags: note.tags,
                lastModified: (mtimeByPath[note.relativePath] ?? nil) ?? .distantPast,  // pre-read stat, see above
                forwardLinks: index.forwardLinks[note.relativePath] ?? [],
                contentSnapshot: contentByPath[note.relativePath] ?? ""))
        }
        try? context.save()
        lastIndexedAt[project] = now
    }
}
