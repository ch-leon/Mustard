import Foundation

/// Pure content provider for the notch's idle rotation.
public enum NotchTicker {
    /// The strings the idle strip rotates through, in order:
    /// plan-your-day prompt → current focus → next meeting → agent-waiting count.
    /// When `planPrompt` is true the prompt leads the rotation and shows even when
    /// everything else is empty (a plan prompt alone is not "All clear").
    public static func idleItems(
        focusTitle: String?, waitingCount: Int, nextEvent: String? = nil, planPrompt: Bool = false
    ) -> [String] {
        var items: [String] = []
        if planPrompt {
            items.append("Plan your day ✦")
        }
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
