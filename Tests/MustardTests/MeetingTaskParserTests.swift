import XCTest
@testable import MustardKit

final class MeetingTaskParserTests: XCTestCase {
    // Pin UTC: due dates parse to midnight UTC, deterministic regardless of zone.
    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func test_harvestsOnlyCodeHeroesTasksSection() {
        let note = """
        # Standup 2026-06-16

        ## Summary
        - [ ] this bullet is prose, not a task we harvest

        ## Code Heroes tasks
        - [ ] Email Kamil the SDK spec 📅 2026-06-20
        - [x] Book the venue ✅ 2026-06-15

        ## Follow-ups
        - [ ] someone else's job
        """
        let tasks = MeetingTaskParser.parse(note, notePath: "meetings/x.md")
        XCTAssertEqual(tasks.map(\.title), ["Email Kamil the SDK spec", "Book the venue"])
    }

    func test_checkboxStates() {
        let note = """
        ## Code Heroes tasks
        - [ ] open one
        - [x] done lower
        - [X] done upper
        """
        XCTAssertEqual(MeetingTaskParser.parse(note, notePath: "m.md").map(\.isDone),
                       [false, true, true])
    }

    func test_parsesDueDate_andNilWhenAbsent() {
        let note = """
        ## Code Heroes tasks
        - [ ] With a due 📅 2026-06-20
        - [ ] No due here
        """
        let tasks = MeetingTaskParser.parse(note, notePath: "m.md")
        XCTAssertEqual(tasks[0].due, at("2026-06-20T00:00:00Z"))
        XCTAssertNil(tasks[1].due)
    }

    func test_blockId_strippedFromTitle_butKeptInRawLine() {
        let note = """
        ## Code Heroes tasks
        - [ ] Refactor the parser ^abc-123
        """
        let t = MeetingTaskParser.parse(note, notePath: "m.md")[0]
        XCTAssertEqual(t.title, "Refactor the parser")
        XCTAssertTrue(t.rawLine.contains("^abc-123"))
    }

    func test_priorityAndDoneEmoji_strippedFromTitle() {
        let note = """
        ## Code Heroes tasks
        - [x] Ship the build 🔼 📅 2026-06-20 ✅ 2026-06-18
        """
        XCTAssertEqual(MeetingTaskParser.parse(note, notePath: "m.md")[0].title, "Ship the build")
    }

    func test_headingTolerance_levelAndTrailingText() {
        let note = """
        ### Code Heroes tasks (Leon)
        - [ ] Do the thing
        """
        XCTAssertEqual(MeetingTaskParser.parse(note, notePath: "m.md").map(\.title), ["Do the thing"])
    }

    func test_noMatchingSection_returnsEmpty() {
        let note = "## Notes\n- [ ] nothing here\n- [x] nor here"
        XCTAssertTrue(MeetingTaskParser.parse(note, notePath: "m.md").isEmpty)
    }

    func test_originKey_stableAcrossTick() {
        // Same line open vs completed must hash identically so a tick doesn't
        // look like a brand-new task on the next sweep.
        let open = "- [ ] Email Kamil the SDK spec 📅 2026-06-20 ^task1"
        let done = "- [x] Email Kamil the SDK spec 📅 2026-06-20 ✅ 2026-06-17 ^task1"
        XCTAssertEqual(
            MeetingTaskParser.originKey(notePath: "meetings/sync.md", line: open),
            MeetingTaskParser.originKey(notePath: "meetings/sync.md", line: done))
    }

    func test_originKey_differsByNoteAndByLine() {
        let line = "- [ ] Same text"
        XCTAssertNotEqual(
            MeetingTaskParser.originKey(notePath: "a.md", line: line),
            MeetingTaskParser.originKey(notePath: "b.md", line: line))
        XCTAssertNotEqual(
            MeetingTaskParser.originKey(notePath: "a.md", line: "- [ ] One"),
            MeetingTaskParser.originKey(notePath: "a.md", line: "- [ ] Two"))
    }
}
