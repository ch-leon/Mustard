import Foundation

public actor ClaudeTaskRuntime: AgentRuntime {
    public typealias CancelInvocation = @Sendable (UUID) -> Void

    private static let activeInvocationMessage = "Claude runtime already has an active invocation."

    private let invoke: ClaudeInvoke
    private let cancelInvocation: CancelInvocation
    private var currentInvocationID: UUID?

    public init(
        invoke: @escaping ClaudeInvoke = ClaudeRunner.invoke,
        cancelInvocation: @escaping CancelInvocation = { ClaudeRunner.cancel($0) }
    ) {
        self.invoke = invoke
        self.cancelInvocation = cancelInvocation
    }

    public func start(_ request: AgentRuntimeRequest) async -> AgentRuntimeResponse {
        await run(request, sessionArgument: "--session-id")
    }

    public func resume(_ request: AgentRuntimeRequest) async -> AgentRuntimeResponse {
        await run(request, sessionArgument: "--resume")
    }

    public func cancel() async {
        guard let currentInvocationID else { return }
        cancelInvocation(currentInvocationID)
    }

    /// Health checks are independent probes and are intentionally not affected by
    /// `cancel()`, which targets only the active task turn.
    public func health() async -> AgentRuntimeHealth {
        let result = await invoke(.init(
            id: UUID(),
            arguments: ["auth", "status", "--json"],
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        ))
        if Self.isLoggedOutAuthStatus(result.text) {
            return .authenticationRequired(result.text)
        }
        if result.ok { return .available }
        if Self.isAuthenticationFailure(result.text) {
            return .authenticationRequired(result.text)
        }
        return .unavailable(result.text)
    }

    /// Task turns are single-flight. The coordinator normally guarantees this; the
    /// adapter also rejects overlap so actor reentrancy cannot replace the ID that
    /// `cancel()` must target.
    private func run(
        _ request: AgentRuntimeRequest,
        sessionArgument: String
    ) async -> AgentRuntimeResponse {
        guard currentInvocationID == nil else {
            return .init(result: nil, failure: .process(Self.activeInvocationMessage))
        }

        let id = UUID()
        currentInvocationID = id
        let result = await invoke(.init(
            id: id,
            arguments: [
                "-p", request.prompt,
                sessionArgument, request.sessionID,
                "--output-format", "json",
                "--json-schema", AgentTurnContract.jsonSchema,
            ],
            workingDirectory: request.workingDirectory
        ))
        if currentInvocationID == id {
            currentInvocationID = nil
        }
        return Self.response(from: result)
    }

    private static func response(from result: ClaudeResult) -> AgentRuntimeResponse {
        if result.unparsed {
            return .init(result: nil, failure: .malformedOutput(result.text))
        }
        if !result.ok {
            return .init(result: nil, failure: classifyFailure(result))
        }
        do {
            return .init(result: try AgentTurnContract.decode(result.text), failure: nil)
        } catch {
            return .init(result: nil, failure: .malformedOutput(result.text))
        }
    }

    /// Authentication and rate limits describe provider-wide failures, so they take
    /// precedence over session text that may be a secondary symptom.
    private static func classifyFailure(_ result: ClaudeResult) -> AgentRuntimeFailure {
        let text = result.text
        if isAuthenticationFailure(text) { return .authenticationRequired(text) }
        if result.rateLimited || ClaudeRunner.isRateLimited(text) { return .rateLimited(text) }
        if isSessionMissing(text) { return .sessionMissing(text) }
        if text.localizedCaseInsensitiveContains("timed out") { return .timedOut(text) }
        return .process(text)
    }

    private static func isAuthenticationFailure(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("401")
            || text.localizedCaseInsensitiveContains("not logged in")
            || text.localizedCaseInsensitiveContains("authentication")
    }

    private static func isLoggedOutAuthStatus(_ text: String) -> Bool {
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        return text.range(of: #""loggedIn"\s*:\s*false"#, options: options) != nil
            || text.range(of: #""authMethod"\s*:\s*"none""#, options: options) != nil
    }

    private static func isSessionMissing(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("no conversation found")
            || text.localizedCaseInsensitiveContains("session not found")
            || text.localizedCaseInsensitiveContains("unknown session")
    }
}
