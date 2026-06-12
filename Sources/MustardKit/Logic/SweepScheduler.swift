import Foundation

/// Pure due-logic for scheduled sweeps. intervalHours == 0 means off.
public enum SweepScheduler {
    public static func isDue(lastSweptAt: Date?, intervalHours: Double, now: Date = .now) -> Bool {
        guard intervalHours > 0 else { return false }
        guard let last = lastSweptAt else { return true }
        return now.timeIntervalSince(last) >= intervalHours * 3600
    }
}
