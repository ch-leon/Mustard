import SwiftUI
import SwiftData
import MustardKit

@main
struct MustardApp: App {
    private let container: ModelContainer
    @State private var agent: AgentService
    @State private var hoverPanel: HoverPanel?
    @State private var notch: NotchController?
    @AppStorage("vaultPath") private var vaultPath = ""
    @AppStorage("sweepIntervalHours") private var sweepIntervalHours = 0.0
    @AppStorage("lastSweptAt") private var lastSweptAt = 0.0

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
                    // Scheduled sweeps (spec decision #5): check every minute,
                    // sweep when the interval has elapsed and the agent is idle.
                    while !Task.isCancelled {
                        if SweepScheduler.isDue(
                            lastSweptAt: lastSweptAt > 0
                                ? Date(timeIntervalSince1970: lastSweptAt) : nil,
                            intervalHours: sweepIntervalHours
                        ), !vaultPath.isEmpty, !agent.isSweeping, !agent.isExecuting {
                            await agent.sweep(vaultPath: vaultPath)
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
