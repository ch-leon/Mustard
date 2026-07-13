import Foundation
import SwiftData

public enum AgentProvider: String, Codable, CaseIterable {
    case claude
    case codex
}

public enum AgentRunState: String, Codable, CaseIterable {
    case queued
    case running
    case needsInput
    case completed
    case failed
    case cancelled
    case interrupted
}

@Model
public final class AgentRun {
    public var uid: String = UUID().uuidString
    public var providerRaw: String = AgentProvider.claude.rawValue
    public var stateRaw: String = AgentRunState.queued.rawValue
    public var providerSessionID: String?
    public var workingDirectory: String = ""
    public var project: String = ""
    public var attemptCount: Int = 0
    public var resumeCount: Int = 0
    public var createdAt: Date = Date.now
    public var startedAt: Date?
    public var lastActivityAt: Date = Date.now
    public var completedAt: Date?
    public var lastOutcomeRaw: String?
    public var lastError: String?
    public var requiresConnectedWorker: Bool = false
    public var task: MustardTask?
    @Relationship(deleteRule: .cascade, inverse: \AgentMessage.run)
    public var messages: [AgentMessage]? = []

    public var provider: AgentProvider {
        get { AgentProvider(rawValue: providerRaw) ?? .claude }
        set { providerRaw = newValue.rawValue }
    }

    public var state: AgentRunState {
        get { AgentRunState(rawValue: stateRaw) ?? .queued }
        set { stateRaw = newValue.rawValue }
    }

    public var orderedMessages: [AgentMessage] {
        (messages ?? []).sorted { $0.sequence < $1.sequence }
    }

    public init(
        task: MustardTask? = nil,
        workingDirectory: String = "",
        project: String = ""
    ) {
        self.task = task
        self.workingDirectory = workingDirectory
        self.project = project
    }
}
