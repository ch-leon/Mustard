import Foundation

/// Pure logic for the mobile Triage swipe deck (BAK-119). The view owns gesture physics
/// and animation; the *decision* — what a swipe means — lives here so it's testable in
/// isolation. Per Leon's call, gated actions (email/Slack/ticket) CAN be approved by a
/// swipe on mobile — approving only queues the draft for the Mac's connected session, it
/// never sends from the phone — so there is no gated special-case here.
public enum TriageDeck {
    /// The three actionable fling directions (a tap opens the detail sheet instead).
    public enum SwipeDirection { case left, right, down }

    /// What a fling resolves to.
    public enum Outcome: Equatable { case approve, reject, snooze }

    /// Right = approve · left = reject · down = snooze.
    public static func outcome(for direction: SwipeDirection) -> Outcome {
        switch direction {
        case .right: return .approve
        case .left: return .reject
        case .down: return .snooze
        }
    }
}
