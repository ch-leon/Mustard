import SwiftUI
import SwiftData
import MustardKit

@main
struct MustardApp: App {
    private let container: ModelContainer
    @State private var agent: AgentService
    @State private var hoverPanel: HoverPanel?
    @State private var notch: NotchController?

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
                .task {
                    let container = container
                    let agent = agent
                    if hoverPanel == nil {
                        hoverPanel = HoverPanel {
                            AnyView(
                                HoverPanelView()
                                    .environment(agent)
                                    .modelContainer(container)
                            )
                        }
                    }
                    if notch == nil {
                        let controller = NotchController { onHover in
                            AnyView(
                                NotchView(onHoverChange: onHover)
                                    .environment(agent)
                                    .modelContainer(container)
                            )
                        }
                        controller.show()
                        notch = controller
                    }
                    // Scheduled multi-source sweeps: each minute, run every enabled +
                    // due source (vault notes), and — throttled to ~10 min — ingest each
                    // project's local `_recs/` (email recs the local routine wrote) into
                    // the same queue. All local; no git.
                    var lastInbox = Date.distantPast
                    while !Task.isCancelled {
                        if !agent.isSweeping, !agent.isExecuting {
                            let settings = SourceSettingsStore.loadOrMigrate()
                            let updated = await agent.sweepDueSources(settings, now: .now)
                            SourceSettingsStore.save(updated)
                            if Date.now.timeIntervalSince(lastInbox) >= 600 {
                                for source in updated.sources where source.enabled && !source.workingDirectory.isEmpty {
                                    await agent.ingestInbox(workingDirectory: source.workingDirectory)
                                }
                                lastInbox = .now
                            }
                        }
                        try? await Task.sleep(for: .seconds(60))
                    }
                }
        }
        .modelContainer(container)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Toggle Hover Panel") { hoverPanel?.toggle() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Toggle Notch") { notch?.toggle() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
