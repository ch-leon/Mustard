import Foundation
import Observation

/// Cross-panel navigation bridge: the notch (its own `NSPanel`) sets a
/// pending request here; `RootView` (the main window) observes it, brings
/// the window forward, and opens the right screen or sheet. Environment-
/// injected into both the notch and the root window, the same way
/// `AgentService` already is (see `MustardApp`).
@MainActor
@Observable
public final class NotchNavigation {
    public var pendingTask: MustardTask?
    public var openAgentConsole = false

    public init() {}
}
