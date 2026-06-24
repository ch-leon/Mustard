import XCTest
@testable import MustardKit

/// Pure selection logic for the one-time backlog prune: which already-imported
/// meeting tasks are stale enough (their meeting was > a week ago) to archive.
final class MeetingTaskCleanupTests: XCTestCase {
    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func meetingTask(path: String) -> MustardTask {
        let t = MustardTask(title: "x")
        t.source = "meeting"
        t.sourceURL = path
        return t
    }

    func test_selectsTasksFromMeetingsOlderThanAWeek_keepsRecent() {
        let old = meetingTask(path: "DL/meetings/2026/05/2026-05-01-sprint-planning.md")
        let recent = meetingTask(path: "DL/meetings/2026/06/2026-06-23-standup.md")

        let stale = MeetingTaskCleanup.tasksToArchive(
            [old, recent], now: at("2026-06-24T00:00:00Z")
        )

        XCTAssertEqual(stale.map(\.sourceURL), [old.sourceURL])
    }

    func test_ignoresNonMeetingTasks() {
        let manual = MustardTask(title: "y")
        manual.source = "manual"
        manual.sourceURL = "DL/meetings/2026/01/2026-01-01-ancient.md"

        let stale = MeetingTaskCleanup.tasksToArchive([manual], now: at("2026-06-24T00:00:00Z"))

        XCTAssertTrue(stale.isEmpty)
    }

    func test_ignoresMeetingTaskWithUnparseableDate() {
        let t = meetingTask(path: "DL/meetings/loose-notes.md")

        let stale = MeetingTaskCleanup.tasksToArchive([t], now: at("2026-06-24T00:00:00Z"))

        XCTAssertTrue(stale.isEmpty)
    }

    func test_keepsTaskDatedExactlyAtCutoff() {
        // now − 7 days == 2026-06-17; "strictly older" means the boundary day is kept.
        let boundary = meetingTask(path: "DL/meetings/2026/06/2026-06-17-standup.md")

        let stale = MeetingTaskCleanup.tasksToArchive([boundary], now: at("2026-06-24T00:00:00Z"))

        XCTAssertTrue(stale.isEmpty)
    }
}
