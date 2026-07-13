import Foundation
import XCTest
@testable import MustardKit

final class ClaudeTaskRuntimeTests: XCTestCase {
    private let sessionID = "11111111-1111-1111-1111-111111111111"
    private let completedJSON = #"{"outcome":"completed","message":"Done","questions":[],"summary":"Done","artifacts":[],"retryDisposition":"none","errorCategory":null,"connectedCapability":null}"#

    func test_start_usesChosenSessionAndSchema_andDecodesCompletedResult() async throws {
        let recorder = InvocationRecorder(result: .init(ok: true, text: completedJSON))
        let runtime = ClaudeTaskRuntime(invoke: recorder.invoke)

        let response = await runtime.start(.init(
            sessionID: sessionID,
            prompt: "do it",
            workingDirectory: "/tmp"
        ))

        XCTAssertEqual(response.result?.outcome, .completed)
        XCTAssertNil(response.failure)
        let invocation = try XCTUnwrap(recorder.invocations.first)
        XCTAssertEqual(invocation.workingDirectory, "/tmp")
        XCTAssertEqual(invocation.arguments, [
            "-p", "do it",
            "--session-id", sessionID,
            "--output-format", "json",
            "--json-schema", AgentTurnContract.jsonSchema,
        ])
    }

    func test_resume_usesResumeFlagAndSameSession() async throws {
        let recorder = InvocationRecorder(result: .init(ok: true, text: completedJSON))
        let runtime = ClaudeTaskRuntime(invoke: recorder.invoke)

        _ = await runtime.resume(.init(
            sessionID: sessionID,
            prompt: "version 2.21",
            workingDirectory: "/tmp"
        ))

        let invocation = try XCTUnwrap(recorder.invocations.first)
        XCTAssertEqual(invocation.arguments, [
            "-p", "version 2.21",
            "--resume", sessionID,
            "--output-format", "json",
            "--json-schema", AgentTurnContract.jsonSchema,
        ])
    }

    func test_authenticationFailures_mapRepresentativeTextCaseInsensitively() async {
        for text in ["HTTP 401", "You are NOT LOGGED IN", "Authentication required"] {
            let runtime = runtime(returning: .init(ok: false, text: text))
            let response = await runtime.start(request())
            XCTAssertEqual(response.failure, .authenticationRequired(text))
        }
    }

    func test_rateLimitFailure_usesRunnerClassification() async {
        let text = "usage limit reached"
        let runtime = runtime(returning: .init(ok: false, text: text, rateLimited: true))

        let response = await runtime.start(request())

        XCTAssertEqual(response.failure, .rateLimited(text))
    }

    func test_sessionMissingFailures_mapRepresentativeTextCaseInsensitively() async {
        for text in ["No conversation found", "SESSION NOT FOUND", "unknown session"] {
            let runtime = runtime(returning: .init(ok: false, text: text))
            let response = await runtime.resume(request())
            XCTAssertEqual(response.failure, .sessionMissing(text))
        }
    }

    func test_errorPrecedence_prefersAuthenticationThenRateLimitThenSessionMissing() async {
        let authAndSession = "401: no conversation found"
        let authResponse = await runtime(returning: .init(
            ok: false, text: authAndSession, rateLimited: true
        )).resume(request())
        XCTAssertEqual(authResponse.failure, .authenticationRequired(authAndSession))

        let rateAndSession = "rate limit: unknown session"
        let rateResponse = await runtime(returning: .init(
            ok: false, text: rateAndSession, rateLimited: true
        )).resume(request())
        XCTAssertEqual(rateResponse.failure, .rateLimited(rateAndSession))
    }

    func test_timeout_mapsTimedOut() async {
        let text = "claude timed out after 1s"
        let response = await runtime(returning: .init(ok: false, text: text)).start(request())
        XCTAssertEqual(response.failure, .timedOut(text))
    }

    func test_unparsedOuterOutput_mapsMalformedOutput() async {
        let text = "plain prose"
        let response = await runtime(returning: .init(
            ok: true, text: text, unparsed: true
        )).start(request())
        XCTAssertEqual(response.failure, .malformedOutput(text))
    }

    func test_malformedInnerContract_mapsMalformedOutput() async {
        let text = #"{"outcome":"completed"}"#
        let response = await runtime(returning: .init(ok: true, text: text)).start(request())
        XCTAssertEqual(response.failure, .malformedOutput(text))
    }

    func test_genericCLIFailure_mapsProcess() async {
        let text = "claude exited 7"
        let response = await runtime(returning: .init(ok: false, text: text)).start(request())
        XCTAssertEqual(response.failure, .process(text))
    }

    func test_health_invokesAuthStatusWithFreshID_andMapsAvailable() async throws {
        let recorder = InvocationRecorder(result: .init(ok: true, text: #"{"loggedIn":true}"#))
        let runtime = ClaudeTaskRuntime(invoke: recorder.invoke)

        let health = await runtime.health()
        XCTAssertEqual(health, .available)

        let invocation = try XCTUnwrap(recorder.invocations.first)
        XCTAssertEqual(invocation.arguments, ["auth", "status", "--json"])
        XCTAssertEqual(
            invocation.workingDirectory,
            FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    func test_health_mapsAuthenticationAndUnavailable() async {
        let authText = "not logged in"
        let authHealth = await runtime(
            returning: .init(ok: false, text: authText)
        ).health()
        XCTAssertEqual(authHealth, .authenticationRequired(authText))

        let unavailableText = "binary failed"
        let unavailableHealth = await runtime(
            returning: .init(ok: false, text: unavailableText)
        ).health()
        XCTAssertEqual(unavailableHealth, .unavailable(unavailableText))
    }

    func test_cancelTargetsOnlyCurrentInvocation_andCompletionClearsIt() async throws {
        let controlled = ControlledInvoke()
        let cancelled = LockedValues<UUID>()
        let runtime = ClaudeTaskRuntime(
            invoke: controlled.invoke,
            cancelInvocation: { cancelled.append($0) }
        )
        let run = Task { await runtime.start(self.request()) }
        let invocation = try await controlled.waitForInvocation()

        await runtime.cancel()
        XCTAssertEqual(cancelled.values, [invocation.id])

        controlled.complete(invocation.id, with: .init(ok: true, text: completedJSON))
        _ = await run.value
        await runtime.cancel()
        XCTAssertEqual(cancelled.values, [invocation.id], "late cancel must not target completed work")
    }

    func test_overlappingTurnIsRejected_withoutReplacingCurrentInvocation() async throws {
        let controlled = ControlledInvoke()
        let cancelled = LockedValues<UUID>()
        let runtime = ClaudeTaskRuntime(
            invoke: controlled.invoke,
            cancelInvocation: { cancelled.append($0) }
        )
        let first = Task { await runtime.start(self.request(prompt: "first")) }
        let firstInvocation = try await controlled.waitForInvocation()

        let second = await runtime.start(request(prompt: "second"))
        XCTAssertEqual(second.failure, .process("Claude runtime already has an active invocation."))
        XCTAssertEqual(controlled.invocations.count, 1)

        await runtime.cancel()
        XCTAssertEqual(cancelled.values, [firstInvocation.id])
        controlled.complete(firstInvocation.id, with: .init(ok: true, text: completedJSON))
        _ = await first.value
    }

    func test_cancelDoesNotTargetHealthInvocation() async throws {
        let controlled = ControlledInvoke()
        let cancelled = LockedValues<UUID>()
        let runtime = ClaudeTaskRuntime(
            invoke: controlled.invoke,
            cancelInvocation: { cancelled.append($0) }
        )
        let health = Task { await runtime.health() }
        let invocation = try await controlled.waitForInvocation()
        XCTAssertEqual(invocation.arguments, ["auth", "status", "--json"])

        await runtime.cancel()
        XCTAssertTrue(cancelled.values.isEmpty)
        controlled.complete(invocation.id, with: .init(ok: true, text: "{}"))
        let healthResult = await health.value
        XCTAssertEqual(healthResult, .available)
    }

    private func request(prompt: String = "do it") -> AgentRuntimeRequest {
        .init(sessionID: sessionID, prompt: prompt, workingDirectory: "/tmp")
    }

    private func runtime(returning result: ClaudeResult) -> ClaudeTaskRuntime {
        ClaudeTaskRuntime(invoke: { _ in result })
    }
}

private final class InvocationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedInvocations: [ClaudeInvocation] = []
    private let result: ClaudeResult

    init(result: ClaudeResult) {
        self.result = result
    }

    var invocations: [ClaudeInvocation] {
        lock.withLock { storedInvocations }
    }

    lazy var invoke: ClaudeInvoke = { [weak self] invocation in
        guard let self else { return ClaudeResult(ok: false, text: "recorder released") }
        self.lock.withLock { self.storedInvocations.append(invocation) }
        return self.result
    }
}

private final class ControlledInvoke: @unchecked Sendable {
    private let lock = NSLock()
    private var storedInvocations: [ClaudeInvocation] = []
    private var continuations: [UUID: CheckedContinuation<ClaudeResult, Never>] = [:]

    var invocations: [ClaudeInvocation] {
        lock.withLock { storedInvocations }
    }

    lazy var invoke: ClaudeInvoke = { [weak self] invocation in
        guard let self else { return ClaudeResult(ok: false, text: "controller released") }
        return await withCheckedContinuation { continuation in
            self.lock.withLock {
                self.storedInvocations.append(invocation)
                self.continuations[invocation.id] = continuation
            }
        }
    }

    func waitForInvocation() async throws -> ClaudeInvocation {
        for _ in 0..<200 {
            if let invocation = invocations.first { return invocation }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NSError(domain: "ClaudeTaskRuntimeTests", code: 1)
    }

    func complete(_ id: UUID, with result: ClaudeResult) {
        let continuation = lock.withLock { continuations.removeValue(forKey: id) }
        continuation?.resume(returning: result)
    }
}

private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []

    var values: [Value] { lock.withLock { stored } }
    func append(_ value: Value) { lock.withLock { stored.append(value) } }
}
