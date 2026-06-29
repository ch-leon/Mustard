import SwiftUI
import SwiftData
import AppKit
import MustardKit

@main
struct MustardApp: App {
    private let container: ModelContainer
    @State private var agent: AgentService
    @State private var calendar: GoogleCalendarService
    @State private var hoverPanel: HoverPanel?
    @State private var notch: NotchController?
    @AppStorage("meetingVaultPath") private var meetingVaultPath = ""

    init() {
        let container = MustardContainer.make()
        self.container = container
        self._agent = State(initialValue: AgentService(context: container.mainContext))

        let keychain = KeychainTokenStore()
        self._calendar = State(initialValue: GoogleCalendarService(
            authSession: GoogleAuthSession(
                makeServer: { LoopbackRedirectServer() },
                tokenClient: GoogleTokenClient(),
                store: keychain,
                openURL: { NSWorkspace.shared.open($0) }),
            tokenClient: GoogleTokenClient(),
            eventsClient: GoogleEventsClient(),
            store: keychain,
            context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(agent)
                .environment(calendar)
                .frame(minWidth: 640, minHeight: 520)
                .task {
                    let container = container
                    let agent = agent
                    calendar.bootstrap()
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
                                    // Agent bridge: export queued/forAgent tasks + ingest results (Phase 2).
                                    let areaName = MeetingTaskSync.defaultAreaMap[source.project] ?? ""
                                    if !areaName.isEmpty {
                                        agent.exportWorkOrders(workingDir: source.workingDirectory, area: areaName, project: source.project)
                                        agent.ingestAgentResults(workingDir: source.workingDirectory)
                                    }
                                }
                                lastInbox = .now
                            }
                        }
                        // One-time backlog prune (2026-06-24 spec): retire the pre-filter
                        // flood of teammates' meeting tasks — mark anything from a meeting
                        // older than a week done (Mustard-only; never touches the vault).
                        if !meetingVaultPath.isEmpty,
                           !UserDefaults.standard.bool(forKey: "didArchiveStaleMeetingTasks") {
                            agent.archiveStaleMeetingTasks()
                            UserDefaults.standard.set(true, forKey: "didArchiveStaleMeetingTasks")
                        }
                        // Meeting-task harvest is cheap (no model call) — reconcile
                        // every tick, independent of the claude sweep interval.
                        if !meetingVaultPath.isEmpty, !agent.isSweeping, !agent.isExecuting {
                            agent.importMeetingTasks(vaultRoot: meetingVaultPath)
                        }
                        // Live Google Calendar: refresh + re-sync when connected.
                        // fetch() calls refreshIfNeeded() internally.
                        if calendar.state == .connected {
                            await calendar.fetch()
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
