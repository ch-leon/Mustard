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
            .filter { $0.decision == .pending } ?? []
        for rec in pending {
            guard TrustPolicy.shouldAutoApprove(
                actionType: rec.proposedActionType, trust: trust, confidence: rec.confidence
            ) else { continue }
            rec.decision = .approved
            let card = await execute(rec)
            if let card, TrustPolicy.shouldAutoAccept(
                actionType: rec.proposedActionType, trust: trust, confidence: rec.confidence
            ) {
                card.review = .accepted
            }
        }
    }

    /// Record feedback on a recommendation without deciding it (stays pending).
    public func comment(_ rec: Recommendation, _ text: String) {
        rec.comment = text
    }

    /// Hide a recommendation until `until`; it reappears in the queue after.
    public func snooze(_ rec: Recommendation, until: Date) {
        rec.snoozedUntil = until
    }

    /// Record a decision. Approval triggers execution, honouring any triage
    /// comment as feedback for the agent on this first run.
    public func decide(_ rec: Recommendation, _ decision: RecommendationDecision) async {
        rec.decision = decision
        if decision == .approved {
            _ = await execute(rec, feedback: rec.comment)
        }
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
