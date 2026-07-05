import Foundation

/// Pure due-logic for the cheap notes reindex (spec addendum #2): minutes, not the
/// hours-scale claude-sweep cadence. Runs inside the existing 60s app loop.
public enum NoteReindexScheduler {
    public static let defaultInterval: TimeInterval = 300
    public static func isDue(lastIndexedAt: Date?, now: Date, interval: TimeInterval = defaultInterval) -> Bool {
        guard let last = lastIndexedAt else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// Pure change-guard for the wholesale reindex: true when disk and the stored
    /// index agree on both the path SET and every path's modification time, so the
    /// rebuild can be skipped (no store churn, no CloudKit traffic). Any added,
    /// removed, or touched file → false → full rebuild. Order-independent on both
    /// sides; a nil disk `modified` (unreadable mtime) never matches a stored date,
    /// so it conservatively forces a rebuild.
    public static func isUnchanged(disk: [(path: String, modified: Date?)],
                                   indexed: [(path: String, modified: Date)]) -> Bool {
        guard disk.count == indexed.count else { return false }
        let indexedByPath = Dictionary(indexed.map { ($0.path, $0.modified) }, uniquingKeysWith: { a, _ in a })
        guard indexedByPath.count == indexed.count else { return false }  // duplicate stored path → rebuild
        for entry in disk {
            guard let storedModified = indexedByPath[entry.path] else { return false }  // path set differs
            guard let diskModified = entry.modified, diskModified == storedModified else { return false }
        }
        return true
    }
}
