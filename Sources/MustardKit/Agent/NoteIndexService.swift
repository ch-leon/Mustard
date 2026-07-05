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
    public private(set) var isIndexing = false
    public private(set) var lastIndexedAt: [String: Date] = [:]   // project → time (in-memory throttle)

    private let context: ModelContext
    private let makeIO: (String) -> NoteVaultIO

    public init(context: ModelContext,
                makeIO: @escaping (String) -> NoteVaultIO = { FileVaultIO(rootPath: $0) }) {
        self.context = context
        self.makeIO = makeIO
    }

    /// 60s-loop entry point: reindex every enabled project whose throttle has lapsed.
    public func reindexDueProjects(_ settings: SourceSettings, now: Date = .now) {
        for config in settings.sources where config.enabled && !config.workingDirectory.isEmpty {
            guard NoteReindexScheduler.isDue(lastIndexedAt: lastIndexedAt[config.project], now: now) else { continue }
            reindex(project: config.project, workingDirectory: config.workingDirectory, now: now)
        }
    }

    /// Manual "Reindex notes now" (⌘K): every enabled project, throttle ignored.
    public func reindexAll(_ settings: SourceSettings, now: Date = .now) {
        for config in settings.sources where config.enabled && !config.workingDirectory.isEmpty {
            reindex(project: config.project, workingDirectory: config.workingDirectory, now: now)
        }
    }

    /// Wholesale rebuild of one project's entries. Also the on-save hook.
    public func reindex(project: String, workingDirectory: String, now: Date = .now) {
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

        // Cheap change-guard (BAK-71 hygiene): if the disk path SET and every
        // (path, mtime) pair already match the stored index, skip the delete+reinsert
        // entirely — just advance the throttle. Avoids disk churn now and CloudKit
        // sync traffic when N2 lands. `notePaths()`/`modificationDate` are stat-only.
        let diskPaths = io.notePaths()
        let disk = diskPaths.map { (path: $0, modified: io.modificationDate($0)) }
        let indexed = existing.map { (path: $0.relativePath, modified: $0.lastModified) }
        if NoteReindexScheduler.isUnchanged(disk: disk, indexed: indexed) {
            lastIndexedAt[project] = now
            return
        }

        let docs = diskPaths.compactMap { path -> (relativePath: String, content: String)? in
            io.read(path).map { (path, $0) }
        }
        let index = WikilinkIndex.build(docs)
        for entry in existing { context.delete(entry) }
        let contentByPath = Dictionary(docs.map { ($0.relativePath, $0.content) }, uniquingKeysWith: { a, _ in a })
        for note in index.notes {
            context.insert(NoteIndexEntry(
                project: project, relativePath: note.relativePath, title: note.title,
                tags: note.tags, lastModified: io.modificationDate(note.relativePath) ?? .distantPast,
                forwardLinks: index.forwardLinks[note.relativePath] ?? [],
                contentSnapshot: contentByPath[note.relativePath] ?? ""))
        }
        try? context.save()
        lastIndexedAt[project] = now
    }
}
