import Foundation

/// Pure content provider for the notch's idle rotation.
public enum NotchTicker {
    /// The strings the idle strip rotates through, in order:
    /// current focus → next meeting → agent-waiting count.
    public static func idleItems(
        focusTitle: String?, waitingCount: Int, nextEvent: String? = nil
    ) -> [String] {
        var items: [String] = []
        if let focus = focusTitle, !focus.isEmpty {
            items.append(focus)
        }
        if let nextEvent, !nextEvent.isEmpty {
            items.append(nextEvent)
        }
        if waitingCount > 0 {
            items.append("\(waitingCount) waiting")
        }
        return items.isEmpty ? ["All clear"] : items
    }

    /// Which item shows at a given tick (one tick = one rotation step).
    public static func item(_ items: [String], tick: Int) -> String {
        guard !items.isEmpty else { return "" }
        return items[tick % items.count]
    }
}
