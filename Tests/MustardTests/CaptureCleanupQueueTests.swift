import XCTest
@testable import MustardKit

/// Pure queue-picking + backoff for the voice-capture cleanup pass (F25 v2, ADR-0011).
final class CaptureCleanupQueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_753_142_400)   // a fixed instant; tests only use offsets

    private func rawTask(_ title: String, createdAt: Date? = nil) -> MustardTask {
        let t = MustardTask(title: title)
        t.captureState = .raw
        t.captureTranscript = title
        if let createdAt { t.createdAt = createdAt }
        return t
    }

    // MARK: - due(_:now:)

    func test_due_picksOnlyRawCaptures() {
        let raw = rawTask("a")
        let plain = MustardTask(title: "b")
        let cleaned = rawTask("c"); cleaned.captureState = .cleaned
        let failed = rawTask("d"); failed.captureState = .failed
        let due = CaptureCleanupQueue.due([plain, cleaned, raw, failed], now: now)
        XCTAssertEqual(due.map(\.title), ["a"])
    }

    func test_due_respectsBackoffWindow() {
        let waiting = rawTask("waiting")
        waiting.captureNextAttemptAt = now.addingTimeInterval(30)   // still closed
        let open = rawTask("open")
        open.captureNextAttemptAt = now.addingTimeInterval(-1)      // window passed
        let due = CaptureCleanupQueue.due([waiting, open], now: now)
        XCTAssertEqual(due.map(\.title), ["open"])
    }

    func test_due_windowExactlyNow_isDue() {
        let t = rawTask("edge")
        t.captureNextAttemptAt = now
        XCTAssertEqual(CaptureCleanupQueue.due([t], now: now).count, 1)
    }

    func test_due_oldestFirst_cappedAtBatchLimit() {
        let tasks = (0..<8).map { i in
            rawTask("t\(i)", createdAt: now.addingTimeInterval(TimeInterval(-i * 60)))
        }
        let due = CaptureCleanupQueue.due(tasks.shuffled(), now: now)
        XCTAssertEqual(due.count, CaptureCleanupQueue.batchLimit)
        // Oldest captures first: t7 (created earliest) leads.
        XCTAssertEqual(due.map(\.title), ["t7", "t6", "t5", "t4", "t3"])
    }

    // MARK: - recordFailure

    func test_recordFailure_walksTheBackoffLadder() {
        let t = rawTask("x")
        CaptureCleanupQueue.recordFailure(t, now: now)
        XCTAssertEqual(t.captureAttempts, 1)
        XCTAssertEqual(t.captureState, .raw)
        XCTAssertEqual(t.captureNextAttemptAt, now.addingTimeInterval(60))

        CaptureCleanupQueue.recordFailure(t, now: now)
        XCTAssertEqual(t.captureNextAttemptAt, now.addingTimeInterval(300))

        CaptureCleanupQueue.recordFailure(t, now: now)
        XCTAssertEqual(t.captureNextAttemptAt, now.addingTimeInterval(900))
    }

    func test_recordFailure_failsAfterLadderExhausted() {
        let t = rawTask("x")
        for _ in 0..<3 { CaptureCleanupQueue.recordFailure(t, now: now) }
        XCTAssertEqual(t.captureState, .raw, "still retrying while ladder has rungs")

        CaptureCleanupQueue.recordFailure(t, now: now)
        XCTAssertEqual(t.captureAttempts, 4)
        XCTAssertEqual(t.captureState, .failed)
        XCTAssertNil(t.captureNextAttemptAt, "a failed capture never re-queues")
    }

    func test_failedTask_isNeverDue() {
        let t = rawTask("x")
        for _ in 0..<4 { CaptureCleanupQueue.recordFailure(t, now: now) }
        XCTAssertTrue(CaptureCleanupQueue.due([t], now: now.addingTimeInterval(9999)).isEmpty)
    }
}
