import XCTest
import SwiftData
@testable import MustardKit

/// In-memory vault: a path→contents map that records writes + snapshots so the
/// write-back path can be asserted without touching disk.
final class FakeVaultIO: MeetingVaultIO {
    var files: [String: String]
    private(set) var snapshots: [String: String] = [:]
    init(_ files: [String: String]) { self.files = files }

    func meetingNotePaths() -> [String] { files.keys.sorted() }
    func read(_ path: String) -> String? { files[path] }
    func write(_ path: String, _ contents: String) throws { files[path] = contents }
    func snapshot(_ path: String, _ contents: String) throws { snapshots[path] = contents }
}

@MainActor
final class MeetingTaskSyncTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self,
            Recommendation.self, AgentRun.self, AgentMessage.self, CalendarEvent.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func note(_ tasks: String) -> String {
        "# Weekly sync 2026-06-16\n\n## Code Heroes tasks\n\(tasks)\n"
    }

    private func tasks(_ ctx: ModelContext) throws -> [MustardTask] {
        try ctx.fetch(FetchDescriptor<MustardTask>())
    }

    func test_import_createsInboxTasks_withProvenance() throws {
        let ctx = try makeContext()
        let io = FakeVaultIO([
            "DL/meetings/sync.md": note("- [ ] Email Kamil the SDK spec 📅 2026-06-20")
        ])
        let sync = MeetingTaskSync(context: ctx, io: io)

        let digest = sync.importTasks()

        let all = try tasks(ctx)
        XCTAssertEqual(all.count, 1)
        let t = all[0]
        XCTAssertEqual(t.title, "Email Kamil the SDK spec")
        XCTAssertEqual(t.status, .inbox)
        XCTAssertEqual(t.owner, .me)
        XCTAssertEqual(t.source, "meeting")
        XCTAssertEqual(t.sourceURL, "DL/meetings/sync.md")
        XCTAssertEqual(t.dueAt, at("2026-06-20T00:00:00Z"))
        XCTAssertNotNil(t.originKey)
        XCTAssertEqual(digest.imported, 1)
    }

    func test_import_isIdempotent_dedupByOriginKey() throws {
        let ctx = try makeContext()
        let io = FakeVaultIO(["DL/meetings/sync.md": note("- [ ] Do the thing")])
        let sync = MeetingTaskSync(context: ctx, io: io)

        _ = sync.importTasks()
        let second = sync.importTasks()

        XCTAssertEqual(try tasks(ctx).count, 1)
        XCTAssertEqual(second.imported, 0)
    }

    func test_archivedMeetingTask_notReimported_andNotWrittenBack() throws {
        let ctx = try makeContext()
        let path = "DL/meetings/old-sync.md"
        let io = FakeVaultIO([path: note("- [ ] Old team task")])
        let sync = MeetingTaskSync(context: ctx, io: io)
        XCTAssertEqual(sync.importTasks().imported, 1)

        // The one-time backlog prune marks the task done and retags its source.
        let t = try XCTUnwrap(try tasks(ctx).first { $0.source == "meeting" })
        t.markDone()
        t.source = "meeting:archived"
        let beforeReimport = io.files[path]

        let again = sync.importTasks()

        XCTAssertEqual(again.imported, 0, "sentinel must still dedupe — no re-flood")
        XCTAssertEqual(try tasks(ctx).count, 1, "no duplicate created")
        XCTAssertEqual(io.files[path], beforeReimport, "archived task must not write ✅ back to the vault")
    }

    func test_import_assignsAreaByVaultRoot() throws {
        let ctx = try makeContext()
        let io = FakeVaultIO([
            "DL/meetings/a.md": note("- [ ] DL task"),
            "Sandvik/meetings/b.md": note("- [ ] Sandvik task"),
        ])
        let sync = MeetingTaskSync(context: ctx, io: io)

        _ = sync.importTasks()

        let byTitle = Dictionary(uniqueKeysWithValues: try tasks(ctx).map { ($0.title, $0) })
        XCTAssertEqual(byTitle["DL task"]?.list?.area?.name, "Digital Licence")
        XCTAssertEqual(byTitle["Sandvik task"]?.list?.area?.name, "Sandvik")
        // Areas are created once and reused.
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Area>()).count, 2)
    }

    func test_import_alreadyCheckedLine_importedAsDone_notResurrected() throws {
        let ctx = try makeContext()
        let io = FakeVaultIO(["DL/meetings/a.md": note("- [x] Already finished ✅ 2026-06-15")])
        let sync = MeetingTaskSync(context: ctx, io: io)

        _ = sync.importTasks()

        let t = try XCTUnwrap(try tasks(ctx).first)
        XCTAssertEqual(t.status, .done)
    }

    func test_import_vaultWonTheRace_completesOpenTask() throws {
        let ctx = try makeContext()
        let open = note("- [ ] Ship it")
        let io = FakeVaultIO(["DL/meetings/a.md": open])
        let sync = MeetingTaskSync(context: ctx, io: io)
        _ = sync.importTasks()
        XCTAssertEqual(try tasks(ctx).first?.status, .inbox)

        // The line gets ticked in the vault out-of-band; next sweep should complete it.
        io.files["DL/meetings/a.md"] = note("- [x] Ship it ✅ 2026-06-17")
        let digest = sync.importTasks()

        XCTAssertEqual(try tasks(ctx).count, 1)
        XCTAssertEqual(try tasks(ctx).first?.status, .done)
        XCTAssertEqual(digest.completedFromVault, 1)
    }

    func test_import_writesBackTasksCompletedInMustard() throws {
        let ctx = try makeContext()
        let io = FakeVaultIO(["DL/meetings/a.md": note("- [ ] Finish me")])
        let sync = MeetingTaskSync(context: ctx, io: io)
        _ = sync.importTasks()
        let t = try XCTUnwrap(try tasks(ctx).first)
        t.markDone(now: at("2026-06-18T09:00:00Z"))  // completed in Mustard

        let digest = sync.importTasks()  // next sweep reconciles back to the vault

        XCTAssertEqual(digest.syncedToVault, 1)
        XCTAssertTrue(try XCTUnwrap(io.files["DL/meetings/a.md"]).contains("- [x] Finish me ✅ 2026-06-18"))
        // Reconciled — a further sweep is a no-op (no duplicate, no re-tick).
        XCTAssertEqual(sync.importTasks().syncedToVault, 0)
    }

    func test_writeBack_snapshotsThenTicksOnlyMatchedLine() throws {
        let ctx = try makeContext()
        let body = note("- [ ] First task\n- [ ] Second task")
        let io = FakeVaultIO(["DL/meetings/a.md": body])
        let sync = MeetingTaskSync(context: ctx, io: io)
        _ = sync.importTasks()
        let first = try XCTUnwrap(try tasks(ctx).first { $0.title == "First task" })

        let ok = sync.completeInVault(first, now: at("2026-06-18T09:00:00Z"))

        XCTAssertTrue(ok)
        // Snapshot taken before the edit, holding the pre-edit contents.
        XCTAssertEqual(io.snapshots["DL/meetings/a.md"], body)
        let updated = try XCTUnwrap(io.files["DL/meetings/a.md"])
        XCTAssertTrue(updated.contains("- [x] First task ✅ 2026-06-18"))
        XCTAssertTrue(updated.contains("- [ ] Second task"))  // untouched
    }

    func test_writeBack_unmatchedLine_skipsAndFlags() throws {
        let ctx = try makeContext()
        let io = FakeVaultIO(["DL/meetings/a.md": note("- [ ] Original task")])
        let sync = MeetingTaskSync(context: ctx, io: io)
        _ = sync.importTasks()
        let t = try XCTUnwrap(try tasks(ctx).first)

        // Note edited out from under us — the line no longer exists.
        io.files["DL/meetings/a.md"] = note("- [ ] A completely different line")
        let ok = sync.completeInVault(t, now: at("2026-06-18T09:00:00Z"))

        XCTAssertFalse(ok)
        XCTAssertNil(io.snapshots["DL/meetings/a.md"])  // no snapshot, no write
        XCTAssertEqual(io.files["DL/meetings/a.md"], note("- [ ] A completely different line"))
    }

    func test_composeNotes_descMeetingOwnerDue() {
        let p = ParsedMeetingTask(
            title: "Move credentials to production", isDone: false,
            due: nil, desc: "Promote the creds to prod.", owner: "Code Heroes",
            dueText: "imminent", transcriptQuote: "targeting production imminently",
            tags: ["creds"], rawLine: "-", notePath: "DL/meetings/2026/04/2026-04-17-x.md",
            originKey: "k")
        let notes = MeetingTaskSync.composeNotes(p, subtitle: "DLA/DLV Feature Showcase")
        XCTAssertEqual(notes, """
        Promote the creds to prod.

        From: DLA/DLV Feature Showcase (2026-04-17)
        Context: "targeting production imminently"
        Owner: Code Heroes · Due: imminent
        """)
    }

    func test_composeNotes_fallsBackToQuoteWhenNoDesc() {
        let p = ParsedMeetingTask(
            title: "Ship it", isDone: false, due: nil, desc: nil, owner: nil,
            dueText: nil, transcriptQuote: "we will ship", tags: [],
            rawLine: "-", notePath: "DL/m.md", originKey: "k")
        let notes = MeetingTaskSync.composeNotes(p, subtitle: "Standup")
        XCTAssertEqual(notes, "we will ship\n\nFrom: Standup")
    }

    func test_import_populatesNotesAndTags() throws {
        let ctx = try makeContext()
        let line = "- [ ] Email Kamil — desc: \"Send the SDK spec to Kamil.\", owner: [[Leon Creed-Baker]], due: 2026-07-15 #task #sdk #ch — [T: \"send Kamil the spec\"]"
        let io = FakeVaultIO(["DL/meetings/2026/06/2026-06-16-sync.md": note(line)])
        let sync = MeetingTaskSync(context: ctx, io: io)

        _ = sync.importTasks()

        let t = try XCTUnwrap(try tasks(ctx).first)
        XCTAssertEqual(t.title, "Email Kamil")
        XCTAssertEqual(t.tags, ["sdk"])
        XCTAssertEqual(t.dueAt, at("2026-07-15T00:00:00Z"))
        XCTAssertTrue(t.notes.contains("Send the SDK spec to Kamil."))
        XCTAssertTrue(t.notes.contains("From: Weekly sync 2026-06-16"))
    }

    func test_import_healsLegacyGiantTitleTaskOnce() throws {
        let ctx = try makeContext()
        let path = "DL/meetings/2026/06/2026-06-16-sync.md"
        let line = "- [ ] Email Kamil — desc: \"Send the SDK spec to Kamil.\", owner: [[Leon Creed-Baker]], due: not stated #task #sdk #ch — [T: \"send Kamil the spec\"]"
        let io = FakeVaultIO([path: note(line)])
        let sync = MeetingTaskSync(context: ctx, io: io)

        // Seed a legacy task: giant title (the raw line), empty notes, same originKey.
        let legacy = MustardTask(title: line, owner: .me)
        legacy.source = "meeting"; legacy.sourceURL = path; legacy.notes = ""
        legacy.originKey = MeetingTaskParser.originKey(notePath: path, line: line)
        ctx.insert(legacy)

        _ = sync.importTasks()
        XCTAssertEqual(try tasks(ctx).count, 1, "healed in place, not duplicated")
        XCTAssertEqual(legacy.title, "Email Kamil")
        XCTAssertTrue(legacy.notes.contains("Send the SDK spec to Kamil."))
        XCTAssertEqual(legacy.tags, ["sdk"])

        // Idempotent: a manual notes edit survives a second sweep.
        legacy.notes = "manually edited"
        _ = sync.importTasks()
        XCTAssertEqual(legacy.notes, "manually edited")
    }

    func test_writeBack_preservesBlockId() throws {
        let ctx = try makeContext()
        let io = FakeVaultIO(["DL/meetings/a.md": note("- [ ] Task with id ^xy7")])
        let sync = MeetingTaskSync(context: ctx, io: io)
        _ = sync.importTasks()
        let t = try XCTUnwrap(try tasks(ctx).first)

        _ = sync.completeInVault(t, now: at("2026-06-18T09:00:00Z"))

        let updated = try XCTUnwrap(io.files["DL/meetings/a.md"])
        XCTAssertTrue(updated.contains("- [x] Task with id ✅ 2026-06-18 ^xy7"))
    }
}
