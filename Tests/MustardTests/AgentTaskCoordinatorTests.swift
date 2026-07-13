import XCTest
import SwiftData
@testable import MustardKit

private actor ScriptedAgentRuntime: AgentRuntime {
    private var responses: [AgentRuntimeResponse]
    private var healthResponses: [AgentRuntimeHealth]
    private var suspendNextInvocation: Bool
    private var suspendCancellation: Bool
    private var invocationContinuation: CheckedContinuation<Void, Never>?
    private var cancellationContinuation: CheckedContinuation<Void, Never>?

    private(set) var startRequests: [AgentRuntimeRequest] = []
    private(set) var resumeRequests: [AgentRuntimeRequest] = []
    private(set) var cancelCount = 0
    private(set) var healthCount = 0

    init(
        responses: [AgentRuntimeResponse] = [],
        healthResponses: [AgentRuntimeHealth] = [],
        suspendNextInvocation: Bool = false,
        suspendCancellation: Bool = false
    ) {
        self.responses = responses
        self.healthResponses = healthResponses
        self.suspendNextInvocation = suspendNextInvocation
        self.suspendCancellation = suspendCancellation
    }

    func start(_ request: AgentRuntimeRequest) async -> AgentRuntimeResponse {
        startRequests.append(request)
        await suspendIfRequested()
        return popResponse()
    }

    func resume(_ request: AgentRuntimeRequest) async -> AgentRuntimeResponse {
        resumeRequests.append(request)
        await suspendIfRequested()
        return popResponse()
    }

    func cancel() async {
        cancelCount += 1
        guard suspendCancellation else { return }
        suspendCancellation = false
        await withCheckedContinuation { continuation in
            cancellationContinuation = continuation
        }
    }

    func health() async -> AgentRuntimeHealth {
        healthCount += 1
        guard !healthResponses.isEmpty else { return .available }
        return healthResponses.removeFirst()
    }

    func releaseInvocation() {
        invocationContinuation?.resume()
        invocationContinuation = nil
    }

    func releaseCancellation() {
        cancellationContinuation?.resume()
        cancellationContinuation = nil
    }

    var invocationCount: Int { startRequests.count + resumeRequests.count }

    private func suspendIfRequested() async {
        guard suspendNextInvocation else { return }
        suspendNextInvocation = false
        await withCheckedContinuation { continuation in
            invocationContinuation = continuation
        }
    }

    private func popResponse() -> AgentRuntimeResponse {
        guard !responses.isEmpty else {
            return .failure(.process("No scripted response"))
        }
        return responses.removeFirst()
    }
}

private extension AgentRuntimeResponse {
    static func completed(
        _ summary: String,
        artifacts: [AgentArtifact] = []
    ) -> Self {
        .success(.init(
            outcome: .completed,
            message: summary,
            questions: [],
            summary: summary,
            artifacts: artifacts,
            retryDisposition: .none,
            errorCategory: nil,
            connectedCapability: nil
        ))
    }

    static func question(_ text: String) -> Self {
        .success(.init(
            outcome: .needsInput,
            message: text,
            questions: [text],
            summary: "",
            artifacts: [],
            retryDisposition: .none,
            errorCategory: nil,
            connectedCapability: nil
        ))
    }

    static func connected(_ capability: String) -> Self {
        .success(.init(
            outcome: .requiresConnectedWorker,
            message: "A connected worker is required for \(capability).",
            questions: [],
            summary: "Waiting for a connected worker",
            artifacts: [],
            retryDisposition: .none,
            errorCategory: nil,
            connectedCapability: capability
        ))
    }

    static func cancelled(_ message: String = "Cancelled") -> Self {
        .success(.init(
            outcome: .cancelled,
            message: message,
            questions: [],
            summary: message,
            artifacts: [],
            retryDisposition: .none,
            errorCategory: nil,
            connectedCapability: nil
        ))
    }
}

@MainActor
final class AgentTaskCoordinatorTests: XCTestCase {
    private let firstTurn = ISO8601DateFormatter().date(from: "2026-07-13T01:00:00Z")!
    private let secondTurn = ISO8601DateFormatter().date(from: "2026-07-13T02:00:00Z")!

    func test_runNextCompletesSimpleTaskIntoReviewWithArtifactLinks() async throws {
        let runtime = ScriptedAgentRuntime(responses: [
            .completed("Release ticket created", artifacts: [
                AgentArtifact(label: "Shortcut", url: "https://app.shortcut.com/story/42"),
            ]),
        ])
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Create release ticket", stage: .forAgent)

        await coordinator.runNext(settings: settings, now: firstTurn)

        let run = try XCTUnwrap(task.agentRun)
        XCTAssertEqual(task.stage, .needsReview)
        XCTAssertEqual(run.state, .completed)
        XCTAssertEqual(run.project, "DL-Knowledge-Base")
        XCTAssertEqual(run.workingDirectory, "/kb/DL")
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(run.providerSessionID)))
        XCTAssertEqual(run.attemptCount, 1)
        XCTAssertEqual(run.startedAt, firstTurn)
        XCTAssertEqual(run.completedAt, firstTurn)
        XCTAssertEqual(run.lastOutcomeRaw, AgentTurnOutcome.completed.rawValue)
        XCTAssertNil(run.lastError)
        XCTAssertEqual(run.orderedMessages.map(\.kind), [.progress, .result])
        XCTAssertEqual(run.orderedMessages.last?.links, [
            TaskLink(label: "Shortcut", url: "https://app.shortcut.com/story/42"),
        ])
        XCTAssertEqual(task.links, run.orderedMessages.last?.links)
        let startCount = await runtime.startRequests.count
        let resumeCount = await runtime.resumeRequests.count
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(resumeCount, 0)
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertNil(coordinator.activeTitle)
    }

    func test_needsInputReleasesSlotAndSecondRunNextRunsNextTask() async throws {
        let runtime = ScriptedAgentRuntime(responses: [
            .question("Which version?"),
            .completed("Other done"),
        ])
        let (coordinator, context) = try fixture(runtime: runtime)
        let first = insertRoutedTask(in: context, title: "Prep release", stage: .forAgent, created: 1)
        let second = insertRoutedTask(in: context, title: "Other", stage: .forAgent, created: 2)

        await coordinator.runNext(settings: settings, now: firstTurn)
        XCTAssertEqual(first.stage, .needsInput)
        XCTAssertEqual(first.agentRun?.state, .needsInput)
        XCTAssertEqual(first.agentRun?.orderedMessages.last?.kind, .question)
        XCTAssertFalse(coordinator.isRunning)

        await coordinator.runNext(settings: settings, now: secondTurn)
        XCTAssertEqual(second.stage, .needsReview)
        let invocationCount = await runtime.invocationCount
        XCTAssertEqual(invocationCount, 2)
    }

    func test_replyRequeuesAndResumeUsesSameSessionAndLatestAnswer() async throws {
        let runtime = ScriptedAgentRuntime(responses: [
            .question("Which version?"),
            .completed("Prepared"),
        ])
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Prep release", stage: .forAgent)
        await coordinator.runNext(settings: settings, now: firstTurn)
        let session = try XCTUnwrap(task.agentRun?.providerSessionID)

        coordinator.reply(to: task, text: "  2.21.0  ", now: secondTurn)

        XCTAssertEqual(task.stage, .queued)
        XCTAssertEqual(task.owner, .agent)
        XCTAssertEqual(task.agentRun?.state, .queued)
        XCTAssertEqual(task.agentRun?.orderedMessages.last?.kind, .answer)
        XCTAssertEqual(task.agentRun?.orderedMessages.last?.content, "2.21.0")
        XCTAssertEqual(task.agentRun?.providerSessionID, session)

        await coordinator.runNext(settings: settings, now: secondTurn)

        let requests = await runtime.resumeRequests
        XCTAssertEqual(requests.map(\.sessionID), [session])
        XCTAssertTrue(try XCTUnwrap(requests.first).prompt.contains("2.21.0"))
        XCTAssertTrue(try XCTUnwrap(requests.first).prompt.contains("Never send email"))
        XCTAssertFalse(try XCTUnwrap(requests.first).prompt.contains("# Mustard delegated-task worker contract"))
        XCTAssertEqual(task.stage, .needsReview)
        XCTAssertEqual(task.agentRun?.resumeCount, 1)
    }

    func test_requestChangesRequeuesAndResumeUsesLatestReviewFeedback() async throws {
        let runtime = ScriptedAgentRuntime(responses: [
            .completed("Draft one"),
            .completed("Draft two"),
        ])
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Write draft", stage: .forAgent)
        await coordinator.runNext(settings: settings, now: firstTurn)
        let session = try XCTUnwrap(task.agentRun?.providerSessionID)

        coordinator.requestChanges(task, feedback: "  Add the migration caveat. ", now: secondTurn)
        XCTAssertEqual(task.stage, .queued)
        XCTAssertEqual(task.agentRun?.orderedMessages.last?.kind, .reviewFeedback)
        XCTAssertFalse(task.agentRun?.requiresConnectedWorker ?? true)

        await coordinator.runNext(settings: settings, now: secondTurn)

        let resumeRequests = await runtime.resumeRequests
        let request = try XCTUnwrap(resumeRequests.first)
        XCTAssertEqual(request.sessionID, session)
        XCTAssertTrue(request.prompt.contains("Add the migration caveat."))
        XCTAssertEqual(task.stage, .needsReview)
    }

    func test_replyRejectsWhitespaceWithoutChangingWaitingTask() async throws {
        let runtime = ScriptedAgentRuntime(responses: [.question("Which version?")])
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Prep release", stage: .forAgent)
        await coordinator.runNext(settings: settings, now: firstTurn)
        let messageCount = try XCTUnwrap(task.agentRun).orderedMessages.count

        coordinator.reply(to: task, text: "  \n\t ", now: secondTurn)

        XCTAssertEqual(task.stage, .needsInput)
        XCTAssertEqual(task.agentRun?.state, .needsInput)
        XCTAssertEqual(task.agentRun?.orderedMessages.count, messageCount)
        XCTAssertEqual(coordinator.lastError, "A reply cannot be empty.")
    }

    func test_requestChangesRequiresExistingRun() throws {
        let runtime = ScriptedAgentRuntime()
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "No run", stage: .needsReview)

        coordinator.requestChanges(task, feedback: "Revise it", now: secondTurn)

        XCTAssertEqual(task.stage, .needsReview)
        XCTAssertNil(task.agentRun)
        XCTAssertEqual(coordinator.lastError, "This task has no agent run to resume.")
    }

    func test_missingRouteLeavesTaskAndExistingRunUnchangedAndReportsError() async throws {
        let runtime = ScriptedAgentRuntime(responses: [.completed("Should not run")])
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = MustardTask(title: "Unrouted", owner: .agent)
        task.stage = .queued
        let run = AgentRun(task: task, workingDirectory: "/old", project: "Old")
        run.state = .failed
        task.agentRun = run
        context.insert(task)
        context.insert(run)
        try context.save()

        await coordinator.runNext(settings: settings, now: firstTurn)

        XCTAssertEqual(task.stage, .queued)
        XCTAssertEqual(run.state, .failed)
        XCTAssertEqual(run.project, "Old")
        XCTAssertEqual(run.workingDirectory, "/old")
        XCTAssertTrue(coordinator.lastError?.contains("route") == true)
        XCTAssertFalse(coordinator.isRunning)
        let invocationCount = await runtime.invocationCount
        XCTAssertEqual(invocationCount, 0)
    }

    func test_malformedOutputRecordsErrorAndRequeuesForLaterPolicy() async throws {
        let runtime = ScriptedAgentRuntime(responses: [
            .failure(.malformedOutput("not-json")),
        ])
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Malformed", stage: .forAgent)

        await coordinator.runNext(settings: settings, now: firstTurn)

        let run = try XCTUnwrap(task.agentRun)
        XCTAssertEqual(task.stage, .queued)
        XCTAssertEqual(run.state, .failed)
        XCTAssertEqual(run.completedAt, firstTurn)
        XCTAssertEqual(run.orderedMessages.last?.kind, .error)
        XCTAssertTrue(run.lastError?.contains("Malformed") == true)
        XCTAssertEqual(coordinator.lastError, run.lastError)
    }

    func test_connectedFallbackIsQueuedFlaggedAndSkippedOnNextSelection() async throws {
        let runtime = ScriptedAgentRuntime(responses: [
            .connected("gmail"),
            .completed("Ordinary task done"),
        ])
        let (coordinator, context) = try fixture(runtime: runtime)
        let connected = insertRoutedTask(in: context, title: "Email draft", stage: .forAgent, created: 1)
        let ordinary = insertRoutedTask(in: context, title: "Local notes", stage: .forAgent, created: 2)

        await coordinator.runNext(settings: settings, now: firstTurn)
        XCTAssertEqual(connected.stage, .queued)
        XCTAssertEqual(connected.agentRun?.state, .queued)
        XCTAssertTrue(connected.agentRun?.requiresConnectedWorker == true)
        XCTAssertEqual(connected.agentRun?.orderedMessages.last?.kind, .recovery)

        await coordinator.runNext(settings: settings, now: secondTurn)
        XCTAssertEqual(ordinary.stage, .needsReview)
        let invocationCount = await runtime.invocationCount
        XCTAssertEqual(invocationCount, 2)
    }

    func test_overlappingRunNextDoesNothingWhileFirstCallIsActive() async throws {
        let runtime = ScriptedAgentRuntime(
            responses: [.completed("First done"), .completed("Second done")],
            suspendNextInvocation: true
        )
        let (coordinator, context) = try fixture(runtime: runtime)
        let first = insertRoutedTask(in: context, title: "First", stage: .forAgent, created: 1)
        let second = insertRoutedTask(in: context, title: "Second", stage: .forAgent, created: 2)

        let active = Task { await coordinator.runNext(settings: settings, now: firstTurn) }
        await waitForInvocation(runtime)
        XCTAssertTrue(coordinator.isRunning)

        await coordinator.runNext(settings: settings, now: secondTurn)
        let invocationCount = await runtime.invocationCount
        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(second.stage, .forAgent)

        await runtime.releaseInvocation()
        await active.value
        XCTAssertEqual(first.stage, .needsReview)
    }

    func test_sessionMissingAllocatesReplacementAndPerformsExactlyOneRecoveryStart() async throws {
        let runtime = ScriptedAgentRuntime(responses: [
            .failure(.sessionMissing("No conversation found")),
            .completed("Recovered"),
        ])
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Resume me", stage: .queued)
        let run = AgentRun(task: task, workingDirectory: "/kb/DL", project: "DL-Knowledge-Base")
        run.providerSessionID = "11111111-1111-1111-1111-111111111111"
        let answer = AgentMessage(run: run, sequence: 4, role: .human, kind: .answer, content: "Latest answer")
        answer.createdAt = firstTurn
        task.agentRun = run
        context.insert(run)
        context.insert(answer)
        try context.save()

        await coordinator.runNext(settings: settings, now: secondTurn)

        let resumes = await runtime.resumeRequests
        let starts = await runtime.startRequests
        XCTAssertEqual(resumes.count, 1)
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(resumes.first?.sessionID, "11111111-1111-1111-1111-111111111111")
        XCTAssertNotEqual(starts.first?.sessionID, resumes.first?.sessionID)
        XCTAssertEqual(run.providerSessionID, starts.first?.sessionID)
        XCTAssertTrue(try XCTUnwrap(starts.first).prompt.contains("Latest answer"))
        XCTAssertEqual(run.orderedMessages.filter { $0.kind == .recovery }.count, 1)
        XCTAssertEqual(run.attemptCount, 2)
        XCTAssertEqual(task.stage, .needsReview)
    }

    func test_repeatedSessionMissingDoesNotLoopAndBecomesNormalFailure() async throws {
        let runtime = ScriptedAgentRuntime(responses: [
            .failure(.sessionMissing("Session missing")),
            .failure(.sessionMissing("Replacement also missing")),
            .completed("Must never be consumed"),
        ])
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Broken session", stage: .queued)
        let run = AgentRun(task: task, workingDirectory: "/kb/DL", project: "DL-Knowledge-Base")
        run.providerSessionID = "22222222-2222-2222-2222-222222222222"
        task.agentRun = run
        context.insert(run)
        try context.save()

        await coordinator.runNext(settings: settings, now: firstTurn)

        let resumeCount = await runtime.resumeRequests.count
        let startCount = await runtime.startRequests.count
        XCTAssertEqual(resumeCount, 1)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(task.stage, .queued)
        XCTAssertEqual(run.state, .failed)
        XCTAssertEqual(run.orderedMessages.last?.kind, .error)
        XCTAssertTrue(run.lastError?.contains("Replacement also missing") == true)
    }

    func test_authenticationFailurePausesGloballyPreservesSessionAndRetryHealthControlsPause() async throws {
        let runtime = ScriptedAgentRuntime(
            responses: [.failure(.authenticationRequired("Please log in"))],
            healthResponses: [.unavailable("CLI unavailable"), .available]
        )
        let (coordinator, context) = try fixture(runtime: runtime)
        let first = insertRoutedTask(in: context, title: "Auth blocked", stage: .forAgent, created: 1)
        _ = insertRoutedTask(in: context, title: "Do not consume", stage: .forAgent, created: 2)

        await coordinator.runNext(settings: settings, now: firstTurn)
        let session = try XCTUnwrap(first.agentRun?.providerSessionID)

        XCTAssertTrue(coordinator.authenticationRequired)
        XCTAssertEqual(first.stage, .queued)
        XCTAssertEqual(first.agentRun?.state, .queued)
        XCTAssertEqual(first.agentRun?.providerSessionID, session)
        XCTAssertNil(first.agentRun?.completedAt)

        await coordinator.runNext(settings: settings, now: secondTurn)
        let invocationCount = await runtime.invocationCount
        XCTAssertEqual(invocationCount, 1)

        await coordinator.retryAuthentication()
        XCTAssertTrue(coordinator.authenticationRequired)
        XCTAssertEqual(coordinator.lastError, "CLI unavailable")

        await coordinator.retryAuthentication()
        XCTAssertFalse(coordinator.authenticationRequired)
        XCTAssertNil(coordinator.lastError)
        let healthCount = await runtime.healthCount
        XCTAssertEqual(healthCount, 2)
    }

    func test_takeBackDuringActiveCallPreservesLocalStateAfterLateSuccess() async throws {
        let runtime = ScriptedAgentRuntime(
            responses: [.completed("Late success")],
            suspendNextInvocation: true
        )
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Take it back", stage: .forAgent)

        let active = Task { await coordinator.runNext(settings: settings, now: firstTurn) }
        await waitForInvocation(runtime)
        coordinator.takeBack(task, now: secondTurn)

        XCTAssertEqual(task.owner, .me)
        XCTAssertEqual(task.stage, .planned)
        XCTAssertEqual(task.agentRun?.state, .cancelled)
        XCTAssertEqual(task.agentRun?.orderedMessages.last?.createdAt, secondTurn)
        await waitForCancel(runtime)

        await runtime.releaseInvocation()
        await active.value
        XCTAssertEqual(task.owner, .me)
        XCTAssertEqual(task.stage, .planned)
        XCTAssertEqual(task.agentRun?.state, .cancelled)
        XCTAssertFalse(task.agentRun?.orderedMessages.contains { $0.content == "Late success" } ?? true)
    }

    func test_cancelActiveImmediatelyCancelsLocalStateAndLateResponseCannotOverwriteIt() async throws {
        let runtime = ScriptedAgentRuntime(
            responses: [.cancelled("Late provider acknowledgement")],
            suspendNextInvocation: true
        )
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Cancel", stage: .forAgent)

        let active = Task { await coordinator.runNext(settings: settings, now: firstTurn) }
        await waitForInvocation(runtime)
        coordinator.cancelActive()

        XCTAssertEqual(task.owner, .me)
        XCTAssertEqual(task.stage, .planned)
        XCTAssertEqual(task.agentRun?.state, .cancelled)
        await waitForCancel(runtime)

        await runtime.releaseInvocation()
        await active.value
        XCTAssertEqual(task.owner, .me)
        XCTAssertEqual(task.stage, .planned)
        XCTAssertEqual(task.agentRun?.state, .cancelled)
    }

    func test_pendingCancellationIsDrainedBeforeCoordinatorCanStartLaterTurn() async throws {
        let runtime = ScriptedAgentRuntime(
            responses: [.completed("Late old result"), .completed("Next done")],
            suspendNextInvocation: true,
            suspendCancellation: true
        )
        let (coordinator, context) = try fixture(runtime: runtime)
        let cancelled = insertRoutedTask(in: context, title: "Cancel old", stage: .forAgent, created: 1)
        let next = insertRoutedTask(in: context, title: "Run next", stage: .forAgent, created: 2)

        let oldTurn = Task { await coordinator.runNext(settings: settings, now: firstTurn) }
        await waitForInvocation(runtime)
        coordinator.takeBack(cancelled, now: secondTurn)
        await waitForCancel(runtime)
        await runtime.releaseInvocation()
        await Task.yield()

        XCTAssertTrue(coordinator.isRunning, "The old turn must retain the serial slot until cancellation drains")
        await coordinator.runNext(settings: settings, now: secondTurn)
        let countWhileCancelling = await runtime.invocationCount
        XCTAssertEqual(countWhileCancelling, 1)
        XCTAssertEqual(next.stage, .forAgent)

        await runtime.releaseCancellation()
        await oldTurn.value
        await coordinator.runNext(settings: settings, now: secondTurn)

        let finalInvocationCount = await runtime.invocationCount
        XCTAssertEqual(finalInvocationCount, 2)
        XCTAssertEqual(next.stage, .needsReview)
    }

    func test_outcomeSaveFailureRollsBackAppliedCompletionAndMessage() async throws {
        let runtime = ScriptedAgentRuntime(
            responses: [.completed("Must not appear applied")],
            suspendNextInvocation: true
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, Recommendation.self,
            AgentRun.self, AgentMessage.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        var saveCount = 0
        let coordinator = AgentTaskCoordinator(context: context, runtime: runtime) {
            saveCount += 1
            if saveCount == 2 { throw CocoaError(.fileWriteUnknown) }
            try context.save()
        }
        let task = insertRoutedTask(in: context, title: "Persistence fails", stage: .forAgent)
        let unrelated = MustardTask(title: "Unrelated edit")
        unrelated.notes = "Saved value"
        context.insert(unrelated)

        let active = Task { await coordinator.runNext(settings: settings, now: firstTurn) }
        await waitForInvocation(runtime)
        unrelated.notes = "Unsaved edit made during agent work"
        await runtime.releaseInvocation()
        await active.value

        let run = try XCTUnwrap(task.agentRun)
        XCTAssertEqual(task.stage, .inProgress)
        XCTAssertEqual(run.state, .running)
        XCTAssertNil(run.completedAt)
        XCTAssertFalse(run.orderedMessages.contains { $0.kind == .result })
        XCTAssertEqual(unrelated.notes, "Unsaved edit made during agent work")
        XCTAssertTrue(coordinator.lastError?.contains("Could not save the agent turn result") == true)
        XCTAssertFalse(coordinator.isRunning)
    }

    func test_runtimeCancelledOutcomeUsesCancellationDecisionWhenNoLocalCancellationOccurred() async throws {
        let runtime = ScriptedAgentRuntime(responses: [.cancelled()])
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Provider cancelled", stage: .forAgent)

        await coordinator.runNext(settings: settings, now: firstTurn)

        XCTAssertEqual(task.owner, .me)
        XCTAssertEqual(task.stage, .planned)
        XCTAssertEqual(task.agentRun?.state, .cancelled)
        XCTAssertEqual(task.agentRun?.lastOutcomeRaw, AgentTurnOutcome.cancelled.rawValue)
    }

    func test_acceptUsesSharedCompletionLogicIncludingRecurrence() throws {
        let runtime = ScriptedAgentRuntime()
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Daily review", stage: .needsReview)
        task.recurrence = .daily
        task.dueAt = firstTurn

        coordinator.accept(task, now: secondTurn)

        let tasks = try context.fetch(FetchDescriptor<MustardTask>())
        XCTAssertEqual(task.stage, .done)
        XCTAssertEqual(task.completedAt, secondTurn)
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks.first { $0.uid != task.uid }?.recurredFrom, task.uid)
    }

    func test_reconcileInterruptedRunsMarksRunAndReturnsOnlyActiveAgentTaskToQueue() throws {
        let runtime = ScriptedAgentRuntime()
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Interrupted", stage: .inProgress)
        let run = AgentRun(task: task, workingDirectory: "/kb/DL", project: "DL-Knowledge-Base")
        run.state = .running
        task.agentRun = run
        context.insert(run)
        try context.save()

        coordinator.reconcileInterruptedRuns(now: secondTurn)

        XCTAssertEqual(task.stage, .queued)
        XCTAssertEqual(run.state, .interrupted)
        XCTAssertEqual(run.orderedMessages.last?.kind, .recovery)
        XCTAssertEqual(run.orderedMessages.last?.createdAt, secondTurn)
        XCTAssertEqual(run.lastActivityAt, secondTurn)
    }

    func test_messagesUseMonotonicSequenceAndPinnedTimestamps() async throws {
        let runtime = ScriptedAgentRuntime(responses: [.question("Choose one")])
        let (coordinator, context) = try fixture(runtime: runtime)
        let task = insertRoutedTask(in: context, title: "Ordered", stage: .forAgent)

        await coordinator.runNext(settings: settings, now: firstTurn)
        coordinator.reply(to: task, text: "Option A", now: secondTurn)

        let run = try XCTUnwrap(task.agentRun)
        XCTAssertEqual(run.orderedMessages.map(\.sequence), [0, 1, 2])
        XCTAssertEqual(run.orderedMessages.map(\.kind), [.progress, .question, .answer])
        XCTAssertEqual(run.orderedMessages.map(\.createdAt), [firstTurn, firstTurn, secondTurn])
        XCTAssertEqual(run.lastActivityAt, secondTurn)
    }

    func test_noTaskDoesNotCallRuntime() async throws {
        let runtime = ScriptedAgentRuntime(responses: [.completed("Unused")])
        let (coordinator, _) = try fixture(runtime: runtime)

        await coordinator.runNext(settings: settings, now: firstTurn)

        let invocationCount = await runtime.invocationCount
        XCTAssertEqual(invocationCount, 0)
        XCTAssertFalse(coordinator.isRunning)
    }

    private var settings: SourceSettings {
        SourceSettings(
            sources: [
                SourceConfig(
                    id: .vault,
                    project: "DL-Knowledge-Base",
                    enabled: true,
                    workingDirectory: "/kb/DL"
                ),
            ],
            state: []
        )
    }

    private func fixture(
        runtime: ScriptedAgentRuntime
    ) throws -> (AgentTaskCoordinator, ModelContext) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Area.self, TaskList.self, MustardTask.self, Recommendation.self,
            AgentRun.self, AgentMessage.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        return (AgentTaskCoordinator(context: context, runtime: runtime), context)
    }

    @discardableResult
    private func insertRoutedTask(
        in context: ModelContext,
        title: String,
        stage: TaskStage,
        created: TimeInterval = 0
    ) -> MustardTask {
        let area = Area(name: "Digital Licence")
        let list = TaskList(name: "Work", area: area)
        let task = MustardTask(title: title, owner: .agent)
        task.stage = stage
        task.createdAt = Date(timeIntervalSince1970: created)
        task.list = list
        context.insert(area)
        context.insert(list)
        context.insert(task)
        return task
    }

    private func waitForInvocation(
        _ runtime: ScriptedAgentRuntime,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10_000 {
            let invocationCount = await runtime.invocationCount
            if invocationCount > 0 { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for runtime invocation", file: file, line: line)
    }

    private func waitForCancel(
        _ runtime: ScriptedAgentRuntime,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10_000 {
            let cancelCount = await runtime.cancelCount
            if cancelCount > 0 { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for runtime cancellation", file: file, line: line)
    }
}
