import SwiftUI
import SwiftData
import MustardKit

@main
struct MustardApp: App {
    private let container: ModelContainer
    @State private var agent: AgentService

    init() {
        let container = MustardContainer.make()
        self.container = container
        self._agent = State(initialValue: AgentService(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(agent)
                .frame(minWidth: 640, minHeight: 520)
        }
        .modelContainer(container)
    }
}
