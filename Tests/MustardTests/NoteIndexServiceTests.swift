import XCTest
import SwiftData
@testable import MustardKit

private final class FakeNoteIO: NoteVaultIO {
    var files: [String: String]
    var mtimes: [String: Date] = [:]
    init(_ files: [String: String]) { self.files = files }
    func notePaths() -> [String] { files.keys.sorted() }
    func read(_ p: String) -> String? { files[p] }
    func write(_ p: String, _ c: String) throws { files[p] = c }
    func snapshot(_ p: String, _ c: String) throws {}
    func modificationDate(_ p: String) -> Date? { mtimes[p] }
}

@MainActor
final class NoteIndexServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, Recommendation.self,
            CalendarEvent.self, NoteIndexEntry.self, configurations: config))
    }
    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    func test_reindex_buildsEntries_titleTagsLinksSnapshot() throws {
        let ctx = try makeContext()
        let io = FakeNoteIO([
            "Home.md": "---\ntags: [hub]\n---\n# Home\ngo [[Setup]]",
            "guides/Setup.md": "# Setup",
        ])
        io.mtimes["Home.md"] = t0
        let svc = NoteIndexService(context: ctx, makeIO: { _ in io })
        svc.reindex(project: "KB", workingDirectory: "/kb", now: t0)
        let entries = try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).sorted { $0.relativePath < $1.relativePath }
        XCTAssertEqual(entries.map(\.relativePath), ["Home.md", "guides/Setup.md"])
        XCTAssertEqual(entries[0].title, "Home")
        XCTAssertEqual(entries[0].tags, ["hub"])
        XCTAssertEqual(entries[0].forwardLinks, ["guides/Setup.md"])
        XCTAssertEqual(entries[0].lastModified, t0)
        XCTAssertEqual(entries[0].project, "KB")
        XCTAssertTrue(entries[0].contentSnapshot.contains("[[Setup]]"))
    }

    func test_reindex_isWholesale_removesDeletedFiles_leavesOtherProjects() throws {
        let ctx = try makeContext()
        ctx.insert(NoteIndexEntry(project: "KB", relativePath: "gone.md"))
        ctx.insert(NoteIndexEntry(project: "Other", relativePath: "keep.md"))
        let svc = NoteIndexService(context: ctx, makeIO: { _ in FakeNoteIO(["new.md": "# N"]) })
        svc.reindex(project: "KB", workingDirectory: "/kb", now: t0)
        let paths = try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).map { "\($0.project)/\($0.relativePath)" }.sorted()
        XCTAssertEqual(paths, ["KB/new.md", "Other/keep.md"])
    }

    func test_reindexDueProjects_respectsThrottle_andSkipsDisabled() throws {
        let ctx = try makeContext()
        let io = FakeNoteIO(["a.md": "# A"])
        let svc = NoteIndexService(context: ctx, makeIO: { _ in io })
        let settings = SourceSettings(sources: [
            SourceConfig(id: .vault, project: "KB", enabled: true, workingDirectory: "/kb"),
            SourceConfig(id: .vault, project: "Off", enabled: false, workingDirectory: "/off"),
        ], state: [])
        svc.reindexDueProjects(settings, now: t0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).map(\.project), ["KB"])
        io.files["b.md"] = "# B"
        svc.reindexDueProjects(settings, now: t0.addingTimeInterval(60))    // throttled — no change
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).count, 1)
        svc.reindexDueProjects(settings, now: t0.addingTimeInterval(301))   // due again
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).count, 2)
    }

    // MARK: Change-guard (skip no-op rebuilds)

    func test_reindex_unchanged_skipsRebuild_entriesNotRecreated() throws {
        let ctx = try makeContext()
        let io = FakeNoteIO(["Home.md": "# Home\n[[Setup]]", "Setup.md": "# Setup"])
        io.mtimes["Home.md"] = t0
        io.mtimes["Setup.md"] = t0
        let svc = NoteIndexService(context: ctx, makeIO: { _ in io })
        svc.reindex(project: "KB", workingDirectory: "/kb", now: t0)
        let idsBefore = Set(try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).map(\.persistentModelID))
        XCTAssertEqual(idsBefore.count, 2)

        // Nothing on disk changed → same PersistentIdentifiers survive (no delete+reinsert).
        svc.reindex(project: "KB", workingDirectory: "/kb", now: t0.addingTimeInterval(600))
        let idsAfter = Set(try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).map(\.persistentModelID))
        XCTAssertEqual(idsAfter, idsBefore)
        // Throttle still advanced so the loop backs off.
        XCTAssertEqual(svc.lastIndexedAt["KB"], t0.addingTimeInterval(600))
    }

    func test_reindex_fileTouched_rebuilds() throws {
        let ctx = try makeContext()
        let io = FakeNoteIO(["Home.md": "# Home"])
        io.mtimes["Home.md"] = t0
        let svc = NoteIndexService(context: ctx, makeIO: { _ in io })
        svc.reindex(project: "KB", workingDirectory: "/kb", now: t0)
        let idBefore = try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).first?.persistentModelID

        io.files["Home.md"] = "# Home renamed"
        io.mtimes["Home.md"] = t0.addingTimeInterval(60)   // touched
        svc.reindex(project: "KB", workingDirectory: "/kb", now: t0.addingTimeInterval(600))
        let entriesAfter = try ctx.fetch(FetchDescriptor<NoteIndexEntry>())
        XCTAssertEqual(entriesAfter.count, 1)
        XCTAssertEqual(entriesAfter[0].title, "Home renamed")
        XCTAssertNotEqual(entriesAfter.first?.persistentModelID, idBefore)  // deleted + reinserted
    }

    func test_reindex_fileAdded_rebuilds() throws {
        let ctx = try makeContext()
        let io = FakeNoteIO(["Home.md": "# Home"])
        io.mtimes["Home.md"] = t0
        let svc = NoteIndexService(context: ctx, makeIO: { _ in io })
        svc.reindex(project: "KB", workingDirectory: "/kb", now: t0)
        io.files["New.md"] = "# New"
        io.mtimes["New.md"] = t0
        svc.reindex(project: "KB", workingDirectory: "/kb", now: t0.addingTimeInterval(600))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).count, 2)
    }

    func test_reindex_fileRemoved_rebuilds() throws {
        let ctx = try makeContext()
        let io = FakeNoteIO(["Home.md": "# Home", "Gone.md": "# Gone"])
        io.mtimes["Home.md"] = t0
        io.mtimes["Gone.md"] = t0
        let svc = NoteIndexService(context: ctx, makeIO: { _ in io })
        svc.reindex(project: "KB", workingDirectory: "/kb", now: t0)
        io.files["Gone.md"] = nil
        io.mtimes["Gone.md"] = nil
        svc.reindex(project: "KB", workingDirectory: "/kb", now: t0.addingTimeInterval(600))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).map(\.relativePath), ["Home.md"])
    }

    func test_reindexAll_bypassesThrottle() throws {
        let ctx = try makeContext()
        let io = FakeNoteIO(["a.md": "# A"])
        let svc = NoteIndexService(context: ctx, makeIO: { _ in io })
        let settings = SourceSettings(sources: [
            SourceConfig(id: .vault, project: "KB", enabled: true, workingDirectory: "/kb"),
        ], state: [])
        svc.reindexDueProjects(settings, now: t0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).count, 1)
        io.files["b.md"] = "# B"
        // 60s later the throttle would block reindexDueProjects (see the test above),
        // but the manual ⌘K path ignores it.
        svc.reindexAll(settings, now: t0.addingTimeInterval(60))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NoteIndexEntry>()).count, 2)
    }
}
