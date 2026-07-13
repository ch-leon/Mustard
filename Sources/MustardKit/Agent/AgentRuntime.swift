import Foundation

public struct AgentRuntimeRequest: Sendable {
    public let sessionID: String
    public let prompt: String
    public let workingDirectory: String

    public init(sessionID: String, prompt: String, workingDirectory: String) {
        self.sessionID = sessionID
        self.prompt = prompt
        self.workingDirectory = workingDirectory
    }
}

public enum AgentRuntimeFailure: Equatable, Sendable {
    case authenticationRequired(String)
    case rateLimited(String)
    case timedOut(String)
    case sessionMissing(String)
    case malformedOutput(String)
    case process(String)
}

public enum AgentRuntimeHealth: Equatable, Sendable {
    case available
    case authenticationRequired(String)
    case unavailable(String)
}

public struct AgentRuntimeResponse: Equatable, Sendable {
    public let result: AgentTurnResult?
    public let failure: AgentRuntimeFailure?

    /// Runtime adapters normally return exactly one of `result` or `failure`.
    public init(result: AgentTurnResult?, failure: AgentRuntimeFailure?) {
        self.result = result
        self.failure = failure
    }
}

public protocol AgentRuntime: Sendable {
    func start(_ request: AgentRuntimeRequest) async -> AgentRuntimeResponse
    func resume(_ request: AgentRuntimeRequest) async -> AgentRuntimeResponse
    func cancel() async
    func health() async -> AgentRuntimeHealth
}
