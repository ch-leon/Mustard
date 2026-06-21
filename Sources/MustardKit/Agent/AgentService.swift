import Foundation
import SwiftData
import Observation

/// Orchestrates the agent loop: sweep → recommendations → decision →
/// execution → output card. Serial: one claude invocation at a time
/// (subscription-friendly).
@MainActor
@Observable
public final class AgentService {
    public private(set) var isSweeping = false
    public private(set) var isExecuting = false
    public private(set) var lastError: String?
    /// Title of the recommendation currently executing (drives the hover panel).
    public private(set) var currentTitle: String?
    /// Digest of the last meeting-task import (e.g. "imported 3 meeting tasks (2 clients)").
    public private(set) var lastMeetingSummary: String?

    private let context: ModelContext
    private let claude: ClaudeRun

    public init(context: ModelContext, claude: @escaping ClaudeRun = ClaudeRunner.run) {
        self.context = context
        self.claude = claude
    }

    /// Manual vault sweep: ask claude for recommendations, ingest them through the
    /// shared pipeline (so manual sweeps dedupe too). Kept as the command-bar /
    /// console entry point during the multi-source transition.
    public func sweep(vaultPath: String) async {
        guard !isSweeping, !vaultPath.isEmpty else { return }
        isSweeping = true
        lastError = nil
        defer { isSweeping = false }

        let result = await claude(VaultSweep.prompt, vaultPath)
        guard result.ok else {
            lastError = "Sweep failed: \(result.text)"
            return
        }
        let project = URL(fileURLWithPath: vaultPath).lastPathComponent
        let proposals = VaultSweep.parse(result.text).map { SourceProposal(vault: $0, project: project) }
        if proposals.isEmpty {
            lastError = "Sweep returned no parseable recommendations"
            return
        }
        ingest(proposals, vaultPath: vaultPath)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastSweptAt")
        await applyTrust(Self.storedTrust())
    }

    /// Harvest meeting tasks from the curated notes under `vaultRoot` and reflect
    /// completions back (bidirectional, idempotent — see `MeetingTaskSync`). Cheap
    /// file I/O + parsing, no model call, so the 60s loop can call it every tick.
    public func importMeetingTasks(vaultRoot: String) {
        guard !vaultRoot.isEmpty else { return }
        let sync = MeetingTaskSync(context: context, io: FileVaultIO(rootPath: vaultRoot))
        let digest = sync.importTasks()
        if digest.imported > 0 || digest.completedFromVault > 0 || digest.syncedToVault > 0 {
            lastMeetingSummary = digest.summary
        }
    }

    /// Scheduled multi-source sweep: run each enabled + due source serially through
    /// the shared pipeline, advance per-source scheduling state only on success, and
    /// run trust once at the end. Returns updated settings for the caller to persist.
    @discardableResult
    public func sweepDueSources(_ settings: SourceSettings, now: Date = .now) async -> SourceSettings {
        guard !isSweeping else { return settings }
        isSweeping = true
        defer { isSweeping = false }

        var updated = settings
        var didIngest = false
        for config in settings.sources where config.enabled {
            // Only the vault source runs locally; Gmail discovery is the cloud scout (ADR-0007).
            guard config.id == .vault else { continue }
            // State is keyed per (source, project) so KBs never clobber each other.
            let state = settings.state.first { $0.id == config.id && $0.project == config.project }
            guard SweepScheduler.isDue(
                lastSweptAt: state?.lastSweptAt, intervalHours: config.intervalHours, now: now
            ) else { continue }

            let result = await claude(VaultSweep.prompt, config.workingDirectory)
            if result.ok {
                let proposals = VaultSweep.parse(result.text).map { SourceProposal(vault: $0, project: config.project) }
                ingest(proposals, vaultPath: config.workingDirectory)
                updated.upsertState(SourceState(id: config.id, project: config.project, lastSweptAt: now, lastError: nil))
                didIngest = true
            } else {
                updated.upsertState(SourceState(id: config.id, project: config.project, lastSweptAt: state?.lastSweptAt, lastError: result.text))
            }
        }
        if didIngest { await applyTrust(Self.storedTrust()) }
        return updated
    }

    /// Single insert pipeline shared by manual + scheduled sweeps: dedupe each
    /// proposal against existing recommendations (and ones accepted earlier in this
    /// batch), then insert non-duplicates with source identity stamped.
    /// Ingest the local routine's grounded recs from a KB folder's `_recs/` through the
    /// shared dedupe + insert pipeline. Files are local (the routine writes them directly
    /// — no git). vaultPath = the KB folder, so any later execution runs in-project.
    public func ingestInbox(workingDirectory: String) async {
        let proposals = InboxIngest.readRecs(in: workingDirectory)
        guard !proposals.isEmpty else { return }
        ingest(proposals, vaultPath: workingDirectory)
        await applyTrust(Self.storedTrust())
    }

    private func ingest(_ proposals: [SourceProposal], vaultPath: String) {
        let existing = (try? context.fetch(FetchDescriptor<Recommendation>())) ?? []
        var accepted: [Recommendation] = []
        for p in proposals where SourceDedupe.shouldInsert(p, against: existing + accepted) {
            let rec = Recommendation(from: p, vaultPath: vaultPath)
            context.insert(rec)
            accepted.append(rec)
        }
    }

    /// Trust level from settings (defaults to manual = nothing auto).
    static func storedTrust() -> TrustLevel {
        TrustLevel(rawValue: UserDefaults.standard.string(forKey: "trustLevel") ?? "") ?? .manual
    }

    /// Auto-process the pending backlog according to trust: approve+execute
    /// eligible recommendations serially, and auto-accept their output when the
    /// level allows. Gated action types are never touched.
    public func applyTrust(_ trust: TrustLevel) async {
        guard trust != .manual else { return }
        let pending = (try? context.fetch(FetchDescriptor<Recommendation>()))?
            .filter { $0.decision == .pending && $0.task == nil } ?? []  // delegated recs gate themselves in delegate()
        for rec in pending {
            if rec.action == .fyi { continue }   // awareness items are never auto-actioned
            guard TrustPolicy.shouldAutoApprove(
                actionType: rec.proposedActionType, trust: trust, confidence: rec.confidence
            ) else { continue }
            rec.decision = .approved
            if rec.action == .createTask { materializeTask(from: rec); continue }
            let card = await execute(rec)
            if let card, TrustPolicy.shouldAutoAccept(
                actionType: rec.proposedActionType, trust: trust, confidence: rec.confidence
            ) {
                accept(card)
            }
        }
    }

    /// Record feedback on a recommendation without deciding it (stays pending).
    public func comment(_ rec: Recommendation, _ text: String) {
        rec.comment = text
    }

    /// Keep an FYI: append it to the project's curated rolling log and clear it from the
    /// queue. No claude run, no OutputCard — filing is a direct local write.
    public func keep(_ rec: Recommendation) {
        let entry = InboxLog.entry(
            title: rec.title, body: rec.originalSource ?? rec.body,
            source: rec.source, sourceURL: rec.sourceURL, now: .now
        )
        let url = InboxLog.logURL(workingDirectory: rec.vaultPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (existing + entry).write(to: url, atomically: true, encoding: .utf8)
        rec.decision = .approved
    }

    /// Hide a recommendation until `until`; it reappears in the queue after.
    public func snooze(_ rec: Recommendation, until: Date) {
        rec.snoozedUntil = until
    }

    /// Approving a create_task lands a real task in the inbox — no claude run, no
    /// OutputCard. The task appearing is the confirmation (mirrors the "I'll do it" button).
    private func materializeTask(from rec: Recommendation) {
        let task = MustardTask(title: rec.title)
        task.notes = rec.draft.isEmpty ? rec.body : rec.draft
        task.status = .inbox
        context.insert(task)
    }

    /// Record a decision. Approval triggers execution, honouring any triage
    /// comment as feedback for the agent on this first run. Denying a delegated
    /// recommendation returns the task to you.
    public func decide(_ rec: Recommendation, _ decision: RecommendationDecision) async {
        rec.decision = decision
        if decision == .denied, let task = rec.task { task.owner = .me }
        guard decision == .approved else { return }
        if rec.action == .fyi { return }   // acknowledging an FYI runs nothing
        if rec.action == .createTask { materializeTask(from: rec); return }
        _ = await execute(rec, feedback: rec.comment)
    }

    /// Delegate a task to the agent ("Ask agent to do this"). Routes the agent's
    /// working directory by the task's client Area (Leon's choice, 2026-06-22), runs a
    /// classify pass, and either queues the proposal (Manual/Supervised) or runs it now
    /// (Trusted+). The agent may decline — then the task stays with you, with a note.
    /// `workVaultRoot`/`sources` default to live settings; tests inject them.
    public func delegate(
        _ task: MustardTask,
        workVaultRoot: String? = nil,
        sources: [SourceConfig]? = nil
    ) async {
        guard !isSweeping, !isExecuting else { return }
        let root = workVaultRoot ?? UserDefaults.standard.string(forKey: "meetingVaultPath") ?? ""
        let configs = sources ?? SourceSettingsStore.loadOrMigrate().sources
        let areaName = task.list?.area?.name

        guard let cwd = AreaRouter.workingDirectory(
            forArea: areaName, sources: configs, workVaultRoot: root
        ) else {
            lastError = "Can't delegate \"\(task.title)\": file it under a client area (Digital Licence, Sales Buddi, Sandvik, Code Heroes) with a configured KB first."
            return
        }

        lastError = nil
        // Hold the serial "one claude at a time" guard across the classify call — the
        // scheduler loop checks isExecuting before sweeping (ADR-0003). Reset right
        // after, before any execute() (which manages isExecuting itself).
        isExecuting = true
        let result = await claude(
            VaultSweep.classifyPrompt(title: task.title, notes: task.notes, areaName: areaName ?? ""),
            cwd
        )
        isExecuting = false

        // A claude failure is NOT a decline — surface it like `sweep` does, never fake "passed".
        guard result.ok else {
            lastError = "Delegation failed: \(result.text)"
            return
        }
        let proposals = VaultSweep.parse(result.text)
        guard let proposal = proposals.first,
              RecommendationAction.from(proposal.actionType) != .ignore else {
            // The agent declined ("ignore") or returned nothing parseable: leave the
            // task with you, with a note. (Unrecognized action types map to vault_note
            // via RecommendationAction.from, so only a literal "ignore" declines.)
            let reason = proposals.first?.draft ?? ""
            task.notes += "\n\n🤖 Agent passed on this" + (reason.isEmpty ? "." : ": \(reason)")
            return
        }

        let rec = Recommendation(
            title: proposal.title, body: proposal.body, actionType: proposal.actionType,
            vaultPath: cwd, confidence: proposal.confidence, reasoning: proposal.reasoning,
            draft: proposal.draft, source: "delegated",
            sourceContext: "Delegated: \(task.title)"
        )
        rec.project = areaName ?? ""
        rec.task = task
        task.delegation = rec
        task.owner = .agent          // flip to agent only once the proposal is real
        context.insert(rec)

        let trust = Self.storedTrust()
        if TrustPolicy.shouldAutoRunDelegation(
            actionType: rec.proposedActionType, trust: trust, confidence: rec.confidence
        ) {
            rec.decision = .approved
            let card = await execute(rec)
            // Only auto-accept a SUCCESSFUL run — never silently complete on failure.
            // A failed run leaves its error card pending in the review queue for you.
            if let card, card.kind != "error", TrustPolicy.shouldAutoAccept(
                actionType: rec.proposedActionType, trust: trust, confidence: rec.confidence
            ) {
                accept(card)
            }
        }
        // else: stays .pending → appears in the Agent console queue for approval.
    }

    /// Accept an output. For a delegated task this closes the loop: mark the task done
    /// and append the agent's output to its Notes (Leon's choice, 2026-06-22). Non-
    /// delegated cards just flip to accepted (sweep/inbox behaviour unchanged).
    public func accept(_ card: OutputCard) {
        // Never complete a task on a failed run (no silent completion); an error card
        // should be Discarded or Revised, not Accepted.
        guard card.kind != "error" else { return }
        card.review = .accepted
        guard let task = card.recommendation?.task else { return }
        if !card.content.isEmpty {
            task.notes += (task.notes.isEmpty ? "" : "\n\n") + "🤖 Agent output:\n\(card.content)"
        }
        task.markDone()
    }

    /// Discard an output. For a delegated task, hand it back to you.
    public func discard(_ card: OutputCard) {
        card.review = .discarded
        if let task = card.recommendation?.task { task.owner = .me }
    }

    /// Re-run a reviewed output with the user's feedback and the prior output as
    /// context, producing a NEW OutputCard. The old card is retired (`.revised`)
    /// only once its replacement exists, so the review queue never empties without
    /// one — and the prior cards stay linked to the recommendation as history.
    @discardableResult
    public func revise(_ card: OutputCard, feedback: String) async -> OutputCard? {
        guard let rec = card.recommendation else { return nil }
        rec.comment = feedback
        let newCard = await execute(rec, feedback: feedback, priorOutput: card.content)
        if newCard != nil { card.review = .revised }
        return newCard
    }

    /// Run an approved recommendation; always produce exactly one OutputCard
    /// per execution (success or failure — no silent completion). The prompt is
    /// grounded in the proposal (action type, draft) and any `feedback`/`priorOutput`
    /// turns it into a revision. Returns the card so callers (auto-accept) can act on it.
    @discardableResult
    public func execute(_ rec: Recommendation, feedback: String = "", priorOutput: String = "") async -> OutputCard? {
        guard !isExecuting else { return nil }
        isExecuting = true
        currentTitle = rec.title
        rec.executionState = .running
        defer { isExecuting = false; currentTitle = nil }

        let result = await claude(
            VaultSweep.executePrompt(
                title: rec.title, body: rec.body, action: rec.action,
                draft: rec.draft, sourceContext: rec.sourceContext,
                feedback: feedback, priorOutput: priorOutput
            ),
            rec.vaultPath
        )
        let card = OutputCard(
            content: result.ok ? result.text : "Execution failed: \(result.text)",
            kind: result.ok ? "summary" : "error",
            recommendation: rec
        )
        context.insert(card)
        rec.executionState = result.ok ? .finished : .failed
        return card
    }
}
