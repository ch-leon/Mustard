import XCTest
@testable import MustardKit

final class NoteReindexSchedulerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)
    func test_neverIndexed_isDue() {
        XCTAssertTrue(NoteReindexScheduler.isDue(lastIndexedAt: nil, now: t0))
    }
    func test_withinInterval_notDue_afterInterval_due() {
        XCTAssertFalse(NoteReindexScheduler.isDue(lastIndexedAt: t0, now: t0.addingTimeInterval(299)))
        XCTAssertTrue(NoteReindexScheduler.isDue(lastIndexedAt: t0, now: t0.addingTimeInterval(300)))
    }

    // MARK: isUnchanged (reindex change-guard)
    private let m0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let m1 = Date(timeIntervalSince1970: 1_700_000_500)

    func test_isUnchanged_samePathsAndMtimes_orderIndependent_true() {
        XCTAssertTrue(NoteReindexScheduler.isUnchanged(
            disk: [("b.md", m1), ("a.md", m0)],
            indexed: [("a.md", m0), ("b.md", m1)]))
    }
    func test_isUnchanged_bothEmpty_true() {
        XCTAssertTrue(NoteReindexScheduler.isUnchanged(disk: [], indexed: []))
    }
    func test_isUnchanged_fileAdded_false() {
        XCTAssertFalse(NoteReindexScheduler.isUnchanged(
            disk: [("a.md", m0), ("b.md", m1)],
            indexed: [("a.md", m0)]))
    }
    func test_isUnchanged_fileRemoved_false() {
        XCTAssertFalse(NoteReindexScheduler.isUnchanged(
            disk: [("a.md", m0)],
            indexed: [("a.md", m0), ("b.md", m1)]))
    }
    func test_isUnchanged_fileTouched_false() {
        XCTAssertFalse(NoteReindexScheduler.isUnchanged(
            disk: [("a.md", m1)],
            indexed: [("a.md", m0)]))
    }
    func test_isUnchanged_renamedSameCount_false() {
        XCTAssertFalse(NoteReindexScheduler.isUnchanged(
            disk: [("a.md", m0), ("c.md", m1)],
            indexed: [("a.md", m0), ("b.md", m1)]))
    }
    func test_isUnchanged_nilDiskMtime_false() {
        XCTAssertFalse(NoteReindexScheduler.isUnchanged(
            disk: [("a.md", nil)],
            indexed: [("a.md", m0)]))
    }
    func test_isUnchanged_duplicateDiskPaths_false() {
        // The FS can't produce a duplicate path, but the pure contract must not
        // permit it either: [(a, a)] vs [(a, b)] would otherwise pass on counts
        // with every disk entry finding a stored match.
        XCTAssertFalse(NoteReindexScheduler.isUnchanged(
            disk: [("a.md", m0), ("a.md", m0)],
            indexed: [("a.md", m0), ("b.md", m1)]))
    }
}
