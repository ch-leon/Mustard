import Foundation

public struct AgentTaskRoute: Equatable, Sendable {
    public let project: String
    public let workingDirectory: String

    public init(project: String, workingDirectory: String) {
        self.project = project
        self.workingDirectory = workingDirectory
    }
}

public enum AgentTaskQueue {
    public static func nextRunnable(_ tasks: [MustardTask]) -> MustardTask? {
        tasks
            .filter {
                $0.owner == .agent
                    && ($0.stage == .forAgent || $0.stage == .queued)
                    && !$0.isBlocked
                    && $0.agentRun?.requiresConnectedWorker != true
            }
            .min(by: precedes)
    }

    /// Sources are considered in settings order; the first eligible source whose
    /// project maps to the task's area is selected.
    public static func route(_ task: MustardTask, settings: SourceSettings) -> AgentTaskRoute? {
        guard let areaName = task.list?.area?.name else { return nil }

        for source in settings.sources {
            guard source.enabled,
                  !source.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  AreaMapping.areaName(forProject: source.project) == areaName
            else { continue }

            return AgentTaskRoute(
                project: source.project,
                workingDirectory: source.workingDirectory
            )
        }

        return nil
    }

    private static func precedes(_ lhs: MustardTask, _ rhs: MustardTask) -> Bool {
        let lhsPriority = priorityRank(lhs.priority)
        let rhsPriority = priorityRank(rhs.priority)
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.uid < rhs.uid
    }

    private static func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .urgent: 0
        case .high: 1
        case .normal: 2
        case .low: 3
        }
    }
}
