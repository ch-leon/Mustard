import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class AgentTaskCoordinator {
    public private(set) var isRunning = false
    public private(set) var activeTitle: String?
    public private(set) var authenticationRequired = false
    public private(set) var lastError: String?

    private let context: ModelContext
    private let runtime: any AgentRuntime
    private let persist: () throws -> Void
    private var activeTask: MustardTask?
    private var activeRun: AgentRun?
    private var activeGeneration = 0
    private var cancellationTask: Task<Void, Never>?

    public init(
        context: ModelContext,
        runtime: any AgentRuntime = ClaudeTaskRuntime()
    ) {
        self.context = context
        self.runtime = runtime
        self.persist = { try context.save() }
    }

    init(
        context: ModelContext,
        runtime: any AgentRuntime,
        persist: @escaping () throws -> Void
    ) {
        self.context = context
        self.runtime = runtime
        self.persist = persist
    }

    public func runNext(settings: SourceSettings, now: Date = .now) async {
        guard !isRunning, !authenticationRequired else { return }

        let tasks: [MustardTask]
        do {
            tasks = try context.fetch(FetchDescriptor<MustardTask>())
        } catch {
            lastError = "Could not load the agent task queue: \(error.localizedDescription)"
            return
        }

        guard let task = AgentTaskQueue.nextRunnable(tasks) else { return }
        guard let route = AgentTaskQueue.route(task, settings: settings) else {
            lastError = "No enabled agent route is configured for “\(task.title)”."
            return
        }

        isRunning = true
        activeTitle = task.title
        lastError = nil
        activeGeneration += 1
        let generation = activeGeneration

        let run = ensureRun(for: task)
        activeTask = task
        activeRun = run
        defer {
            isRunning = false
            activeTitle = nil
            activeTask = nil
            activeRun = nil
        }

        run.project = route.project
        run.workingDirectory = route.workingDirectory
        let startsNewSession = run.providerSessionID == nil
        if startsNewSession {
            run.providerSessionID = UUID().uuidString
        }

        task.stage = .inProgress
        run.state = .running
        run.requiresConnectedWorker = false
        run.startedAt = run.startedAt ?? now
        run.completedAt = nil
        run.lastError = nil
        run.attemptCount += 1
        if !startsNewSession { run.resumeCount += 1 }
        append(
            to: run,
            role: .system,
            kind: .progress,
            content: startsNewSession ? "Agent started work." : "Agent resumed work.",
            now: now
        )

        guard save("Could not persist the agent turn before execution") else {
            restoreFailedTurn(
                task: task,
                run: run,
                detail: lastError ?? "Could not persist the agent turn.",
                now: now,
                kind: .error
            )
            return
        }

        let contract: String
        do {
            contract = try AgentTurnContract.workerContract()
        } catch {
            guard isCurrent(task: task, run: run, generation: generation) else { return }
            restoreFailedTurn(
                task: task,
                run: run,
                detail: "Could not load the worker contract: \(error.localizedDescription)",
                now: now,
                kind: .error
            )
            return
        }

        let sessionID = run.providerSessionID ?? UUID().uuidString
        let prompt: String
        let response: AgentRuntimeResponse
        if startsNewSession {
            prompt = AgentTaskPrompt.firstTurn(
                task: task,
                run: run,
                contract: contract,
                approvedInstructions: []
            )
            response = await runtime.start(.init(
                sessionID: sessionID,
                prompt: prompt,
                workingDirectory: route.workingDirectory
            ))
        } else {
            prompt = AgentTaskPrompt.resume(
                run: run,
                latestHumanMessage: latestHumanContent(in: run, fallback: task.title),
                contractReminder: contractReminder(from: contract),
                approvedInstructions: []
            )
            response = await runtime.resume(.init(
                sessionID: sessionID,
                prompt: prompt,
                workingDirectory: route.workingDirectory
            ))
        }

        await drainPendingCancellation()
        guard isCurrent(task: task, run: run, generation: generation) else { return }

        if case .sessionMissing(let detail)? = response.failure {
            await recoverMissingSession(
                task: task,
                run: run,
                route: route,
                contract: contract,
                detail: detail,
                generation: generation,
                now: now
            )
            return
        }

        apply(response, to: task, run: run, generation: generation, now: now)
    }

    public func reply(to task: MustardTask, text: String, now: Date = .now) {
        queueHumanTurn(task, text: text, kind: .answer, now: now)
    }

    public func requestChanges(
        _ task: MustardTask,
        feedback: String,
        now: Date = .now
    ) {
        queueHumanTurn(task, text: feedback, kind: .reviewFeedback, now: now)
    }

    public func accept(_ task: MustardTask, now: Date = .now) {
        TaskCompletion.complete(task, in: context, now: now)
        _ = save("Could not save the accepted task")
    }

    public func takeBack(_ task: MustardTask, now: Date = .now) {
        let run = task.agentRun
        task.owner = .me
        task.stage = .planned
        if let run {
            run.state = .cancelled
            run.requiresConnectedWorker = false
            run.completedAt = now
            run.lastOutcomeRaw = AgentTurnOutcome.cancelled.rawValue
            run.lastError = nil
            append(
                to: run,
                role: .system,
                kind: .recovery,
                content: "Task taken back by you; active agent work was cancelled.",
                now: now
            )
        }
        _ = save("Could not save the taken-back task")

        if activeTask === task {
            activeGeneration += 1
            requestRuntimeCancellation()
        }
    }

    public func cancelActive() {
        guard let task = activeTask, let run = activeRun else { return }
        activeGeneration += 1

        if task.owner == .agent, task.stage == .inProgress, run.state == .running {
            applyCancellation(
                task: task,
                run: run,
                detail: "Active agent work was cancelled by you.",
                now: .now,
                role: .system
            )
        }
        requestRuntimeCancellation()
    }

    public func retryAuthentication() async {
        switch await runtime.health() {
        case .available:
            authenticationRequired = false
            lastError = nil
        case .authenticationRequired(let detail), .unavailable(let detail):
            authenticationRequired = true
            lastError = detail.isEmpty
                ? "The agent runtime is still unavailable."
                : detail
        }
    }

    public func reconcileInterruptedRuns(now: Date = .now) {
        let runs: [AgentRun]
        do {
            runs = try context.fetch(FetchDescriptor<AgentRun>())
        } catch {
            lastError = "Could not reconcile interrupted agent runs: \(error.localizedDescription)"
            return
        }

        for run in runs where run.state == .running {
            run.state = .interrupted
            run.completedAt = nil
            run.lastError = "The app stopped while this agent turn was running."
            if let task = run.task,
               task.owner == .agent,
               task.stage == .inProgress {
                task.stage = .queued
            }
            append(
                to: run,
                role: .system,
                kind: .recovery,
                content: "Recovered an interrupted run and returned it to the queue.",
                now: now
            )
        }
        _ = save("Could not save interrupted-run recovery")
    }

    private func recoverMissingSession(
        task: MustardTask,
        run: AgentRun,
        route: AgentTaskRoute,
        contract: String,
        detail: String,
        generation: Int,
        now: Date
    ) async {
        guard isCurrent(task: task, run: run, generation: generation) else { return }

        let replacementSessionID = UUID().uuidString
        run.providerSessionID = replacementSessionID
        run.attemptCount += 1
        append(
            to: run,
            role: .system,
            kind: .recovery,
            content: "Provider session was unavailable; starting a replacement session. \(detail)",
            now: now
        )
        guard save("Could not persist provider-session recovery") else {
            restoreFailedTurn(
                task: task,
                run: run,
                detail: lastError ?? "Could not persist provider-session recovery.",
                now: now,
                kind: .error
            )
            return
        }

        let recoveryPrompt = AgentTaskPrompt.recovery(
            task: task,
            run: run,
            contract: contract,
            approvedInstructions: []
        )
        let recoveryResponse = await runtime.start(.init(
            sessionID: replacementSessionID,
            prompt: recoveryPrompt,
            workingDirectory: route.workingDirectory
        ))

        await drainPendingCancellation()
        guard isCurrent(task: task, run: run, generation: generation) else { return }
        apply(recoveryResponse, to: task, run: run, generation: generation, now: now)
    }

    private func apply(
        _ response: AgentRuntimeResponse,
        to task: MustardTask,
        run: AgentRun,
        generation: Int,
        now: Date
    ) {
        guard isCurrent(task: task, run: run, generation: generation) else { return }

        if let result = response.result {
            apply(result, to: task, run: run, now: now)
            return
        }
        guard let failure = response.failure else {
            restoreFailedTurn(
                task: task,
                run: run,
                detail: "The agent runtime returned neither a result nor a failure.",
                now: now,
                kind: .error
            )
            return
        }

        switch failure {
        case .authenticationRequired(let detail):
            let message = detail.isEmpty ? "Agent authentication is required." : detail
            authenticationRequired = true
            lastError = message
            task.stage = .queued
            run.state = .queued
            run.completedAt = nil
            run.lastError = message
            append(to: run, role: .system, kind: .error, content: message, now: now)
            _ = save("Could not save the authentication pause")

        case .cancelled(let detail):
            applyCancellation(
                task: task,
                run: run,
                detail: detail.isEmpty ? "The agent runtime cancelled the turn." : detail,
                now: now,
                role: .agent
            )

        case .rateLimited(let detail):
            restoreFailedTurn(
                task: task,
                run: run,
                detail: failureDescription("Rate limited", detail),
                now: now,
                kind: .error
            )
        case .timedOut(let detail):
            restoreFailedTurn(
                task: task,
                run: run,
                detail: failureDescription("Timed out", detail),
                now: now,
                kind: .error
            )
        case .sessionMissing(let detail):
            // The sole recovery attempt has already been consumed before this path.
            restoreFailedTurn(
                task: task,
                run: run,
                detail: failureDescription("Replacement session missing", detail),
                now: now,
                kind: .error
            )
        case .malformedOutput(let detail):
            restoreFailedTurn(
                task: task,
                run: run,
                detail: failureDescription("Malformed agent output", detail),
                now: now,
                kind: .error
            )
        case .process(let detail):
            restoreFailedTurn(
                task: task,
                run: run,
                detail: failureDescription("Agent process failed", detail),
                now: now,
                kind: .error
            )
        }
    }

    private func apply(
        _ result: AgentTurnResult,
        to task: MustardTask,
        run: AgentRun,
        now: Date
    ) {
        let previousTaskStage = task.stage
        let previousTaskOwner = task.owner
        let previousTaskLinks = task.links
        let previousRunState = run.state
        let previousConnectedWorker = run.requiresConnectedWorker
        let previousOutcome = run.lastOutcomeRaw
        let previousRunError = run.lastError
        let previousCompletedAt = run.completedAt
        let previousActivityAt = run.lastActivityAt

        let decision = AgentTaskTransition.decision(for: result.outcome)
        task.stage = decision.taskStage
        if let owner = decision.taskOwner { task.owner = owner }
        run.state = decision.runState
        run.requiresConnectedWorker = decision.requiresConnectedWorker
        run.lastOutcomeRaw = result.outcome.rawValue
        run.lastError = nil

        let outcomeMessage: AgentMessage
        switch result.outcome {
        case .needsInput:
            run.completedAt = nil
            let questions = result.questions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            outcomeMessage = append(
                to: run,
                role: .agent,
                kind: .question,
                content: questions.isEmpty ? result.message : questions,
                now: now
            )

        case .completed:
            run.completedAt = now
            let links = result.artifacts.map { TaskLink(label: $0.label, url: $0.url) }
            merge(links, into: task)
            outcomeMessage = append(
                to: run,
                role: .agent,
                kind: .result,
                content: result.summary.isEmpty ? result.message : result.summary,
                links: links,
                now: now
            )

        case .failed:
            run.completedAt = now
            let category = result.errorCategory ?? "Agent task failed"
            let detail = result.message.isEmpty ? category : "\(category): \(result.message)"
            run.lastError = detail
            lastError = detail
            outcomeMessage = append(
                to: run,
                role: .agent,
                kind: .error,
                content: detail,
                now: now
            )

        case .cancelled:
            run.completedAt = now
            outcomeMessage = append(
                to: run,
                role: .agent,
                kind: .recovery,
                content: result.message.isEmpty ? "The agent cancelled this task." : result.message,
                now: now
            )

        case .requiresConnectedWorker:
            run.completedAt = nil
            let capability = result.connectedCapability ?? "a connected capability"
            let detail = result.message.isEmpty
                ? "Connected worker required: \(capability)."
                : result.message
            outcomeMessage = append(
                to: run,
                role: .agent,
                kind: .recovery,
                content: detail,
                now: now
            )
        }

        guard save("Could not save the agent turn result") else {
            let persistenceError = lastError
            task.stage = previousTaskStage
            task.owner = previousTaskOwner
            task.links = previousTaskLinks
            run.state = previousRunState
            run.requiresConnectedWorker = previousConnectedWorker
            run.lastOutcomeRaw = previousOutcome
            run.lastError = previousRunError
            run.completedAt = previousCompletedAt
            run.lastActivityAt = previousActivityAt
            run.messages = run.messages?.filter { $0 !== outcomeMessage }
            outcomeMessage.run = nil
            context.delete(outcomeMessage)
            lastError = persistenceError
            return
        }
    }

    private func queueHumanTurn(
        _ task: MustardTask,
        text: String,
        kind: AgentMessageKind,
        now: Date
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "A reply cannot be empty."
            return
        }
        guard let run = task.agentRun else {
            lastError = "This task has no agent run to resume."
            return
        }

        append(to: run, role: .human, kind: kind, content: trimmed, now: now)
        task.owner = .agent
        task.stage = .queued
        run.state = .queued
        run.requiresConnectedWorker = false
        run.completedAt = nil
        run.lastError = nil
        lastError = nil
        _ = save("Could not save the agent reply")
    }

    private func ensureRun(for task: MustardTask) -> AgentRun {
        if let run = task.agentRun { return run }
        let run = AgentRun(task: task)
        task.agentRun = run
        context.insert(run)
        return run
    }

    @discardableResult
    private func append(
        to run: AgentRun,
        role: AgentMessageRole,
        kind: AgentMessageKind,
        content: String,
        links: [TaskLink] = [],
        now: Date
    ) -> AgentMessage {
        let sequence = (run.messages?.map(\.sequence).max() ?? -1) + 1
        let message = AgentMessage(
            run: run,
            sequence: sequence,
            role: role,
            kind: kind,
            content: content,
            links: links
        )
        message.createdAt = now
        context.insert(message)
        run.lastActivityAt = now
        return message
    }

    private func restoreFailedTurn(
        task: MustardTask,
        run: AgentRun,
        detail: String,
        now: Date,
        kind: AgentMessageKind
    ) {
        guard task.owner == .agent,
              task.stage == .inProgress,
              run.state == .running
        else { return }

        task.stage = .queued
        run.state = .failed
        run.completedAt = now
        run.lastOutcomeRaw = nil
        run.lastError = detail
        lastError = detail
        append(to: run, role: .system, kind: kind, content: detail, now: now)
        _ = save("Could not save the failed agent turn")
    }

    private func applyCancellation(
        task: MustardTask,
        run: AgentRun,
        detail: String,
        now: Date,
        role: AgentMessageRole
    ) {
        let decision = AgentTaskTransition.decision(for: .cancelled)
        task.stage = decision.taskStage
        if let owner = decision.taskOwner { task.owner = owner }
        run.state = decision.runState
        run.requiresConnectedWorker = false
        run.completedAt = now
        run.lastOutcomeRaw = AgentTurnOutcome.cancelled.rawValue
        run.lastError = nil
        append(to: run, role: role, kind: .recovery, content: detail, now: now)
        _ = save("Could not save the cancelled agent turn")
    }

    private func isCurrent(
        task: MustardTask,
        run: AgentRun,
        generation: Int
    ) -> Bool {
        activeGeneration == generation
            && activeTask === task
            && activeRun === run
            && task.owner == .agent
            && task.stage == .inProgress
            && run.state == .running
    }

    private func latestHumanContent(in run: AgentRun, fallback: String) -> String {
        run.orderedMessages.reversed().first {
            $0.role == .human && ($0.kind == .answer || $0.kind == .reviewFeedback)
        }?.content
            ?? run.orderedMessages.reversed().first { $0.role == .human }?.content
            ?? fallback
    }

    private func contractReminder(from contract: String) -> String {
        let prefixes = [
            "Work only", "Ask focused", "Never ", "Verify every", "Every completed",
            "Return only", "Mustard task UID", "The coordinator",
        ]
        let selected = contract
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                prefixes.contains { line.hasPrefix($0) }
                    || line.contains("Never send email")
            }
        return selected.isEmpty
            ? "Follow the binding worker safety and structured-output contract from the first turn."
            : selected.joined(separator: "\n")
    }

    private func merge(_ links: [TaskLink], into task: MustardTask) {
        var seen = Set(task.links.map { "\($0.label)\u{0}\($0.url)" })
        for link in links where seen.insert("\(link.label)\u{0}\(link.url)").inserted {
            task.links.append(link)
        }
    }

    private func failureDescription(_ prefix: String, _ detail: String) -> String {
        detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? prefix
            : "\(prefix): \(detail)"
    }

    @discardableResult
    private func save(_ prefix: String) -> Bool {
        do {
            try persist()
            return true
        } catch {
            lastError = "\(prefix): \(error.localizedDescription)"
            return false
        }
    }

    private func requestRuntimeCancellation() {
        guard cancellationTask == nil else { return }
        let runtime = runtime
        cancellationTask = Task {
            await runtime.cancel()
        }
    }

    private func drainPendingCancellation() async {
        guard let cancellationTask else { return }
        await cancellationTask.value
        self.cancellationTask = nil
    }
}
