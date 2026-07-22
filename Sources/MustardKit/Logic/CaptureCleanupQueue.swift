import Foundation

/// Pure queue-picking + backoff for the voice-capture cleanup pass (F25 v2,
/// ADR-0011). Which raw captures go into the next batched `claude -p` call, and
/// how a failed pass backs off — the same 60/300/900s ladder as
/// `AgentRetryPolicy`, after which the capture parks as `.failed` (the task stays
/// usable with its raw title; it is never silently dropped).
public enum CaptureCleanupQueue {
    /// One cleanup call handles at most this many captures (mirrors the sweep's ≤5).
    public static let batchLimit = 5
    /// Backoff after the n-th consecutive failure; a failure beyond the last rung
    /// parks the capture as `.failed`.
    public static let backoffSeconds: [TimeInterval] = [60, 300, 900]

    /// Raw captures whose backoff window has passed, oldest capture first, capped
    /// at `batchLimit`.
    public static func due(_ tasks: [MustardTask], now: Date) -> [MustardTask] {
        Array(
            tasks
                .filter { $0.captureState == .raw }
                .filter { ($0.captureNextAttemptAt ?? .distantPast) <= now }
                .sorted { $0.createdAt < $1.createdAt }
                .prefix(batchLimit)
        )
    }

    /// Record one failed cleanup attempt: advance the ladder, or park as `.failed`
    /// once it's exhausted. Mutates only the task's capture columns.
    public static func recordFailure(_ task: MustardTask, now: Date) {
        task.captureAttempts += 1
        if task.captureAttempts <= backoffSeconds.count {
            task.captureNextAttemptAt = now.addingTimeInterval(backoffSeconds[task.captureAttempts - 1])
        } else {
            task.captureState = .failed
            task.captureNextAttemptAt = nil
        }
    }
}
