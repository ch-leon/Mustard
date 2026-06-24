import SwiftUI

/// App-level state for the source inspector: which link is shown and whether the
/// panel is open. Owned by `RootView` and injected into its subtree via the
/// environment, mirroring how `AgentService` is provided. A single reused web
/// view re-points each time `open` is called (no tabs).
@Observable
public final class SourcePanelController {
    public var current: SourceLink?
    public var isPresented: Bool = false

    public init() {}

    public func open(_ link: SourceLink) {
        current = link
        isPresented = true
    }
}
