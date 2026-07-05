import Foundation

/// Pure due-logic for the cheap notes reindex (spec addendum #2): minutes, not the
/// hours-scale claude-sweep cadence. Runs inside the existing 60s app loop.
public enum NoteReindexScheduler {
    public static let defaultInterval: TimeInterval = 300
    public static func isDue(lastIndexedAt: Date?, now: Date, interval: TimeInterval = defaultInterval) -> Bool {
        guard let last = lastIndexedAt else { return true }
        return now.timeIntervalSince(last) >= interval
    }
}
