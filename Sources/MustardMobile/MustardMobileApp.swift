import SwiftUI
import SwiftData

/// iOS companion entry point (BAK-108 foundation, BAK-110 shell). Wires the shared
/// MustardKit `ModelContainer` + `AgentService` (the agent's execution is a Mac-only
/// no-op on iOS — ADR-0003) into a bottom-tab shell. The four screens fill in at
/// BAK-113/114/116/119.
@main
struct MustardMobileApp: App {
    @State private var agent: AgentService
    private let container: ModelContainer

    init() {
        let container = MustardContainer.make()
        self.container = container
        self._agent = State(initialValue: AgentService(context: container.mainContext))
        #if DEBUG
        MobileSampleData.seedIfEmpty(container.mainContext)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environment(agent)
                .modelContainer(container)
        }
    }
}
