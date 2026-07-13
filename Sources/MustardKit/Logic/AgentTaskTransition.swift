public struct AgentTransitionDecision: Equatable {
    public let taskStage: TaskStage
    public let runState: AgentRunState
    public let releasesSlot: Bool
    public let requiresConnectedWorker: Bool

    public init(
        taskStage: TaskStage,
        runState: AgentRunState,
        releasesSlot: Bool,
        requiresConnectedWorker: Bool = false
    ) {
        self.taskStage = taskStage
        self.runState = runState
        self.releasesSlot = releasesSlot
        self.requiresConnectedWorker = requiresConnectedWorker
    }
}

public enum AgentTaskTransition {
    public static func decision(for outcome: AgentTurnOutcome) -> AgentTransitionDecision {
        switch outcome {
        case .needsInput:
            AgentTransitionDecision(
                taskStage: .needsInput,
                runState: .needsInput,
                releasesSlot: true
            )
        case .completed:
            AgentTransitionDecision(
                taskStage: .needsReview,
                runState: .completed,
                releasesSlot: true
            )
        case .requiresConnectedWorker:
            AgentTransitionDecision(
                taskStage: .queued,
                runState: .queued,
                releasesSlot: true,
                requiresConnectedWorker: true
            )
        case .failed:
            AgentTransitionDecision(
                taskStage: .queued,
                runState: .failed,
                releasesSlot: true
            )
        case .cancelled:
            AgentTransitionDecision(
                taskStage: .planned,
                runState: .cancelled,
                releasesSlot: true
            )
        }
    }
}
