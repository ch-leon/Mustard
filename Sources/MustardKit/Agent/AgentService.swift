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

    /// Sweep the vault: ask claude for recommendations, insert them pending.
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
        let proposals = VaultSweep.parse(result.text)
        if proposals.isEmpty {
            lastError = "Sweep returned no parseable recommendations"
            return
        }
        for proposal in proposals {
            let rec = Recommendation(
                title: proposal.title, body: proposal.body,
                actionType: proposal.actionType, vaultPath: vaultPath,
                confidence: proposal.confidence, reasoning: proposal.reasoning,
                draft: proposal.draft
            )
            context.insert(rec)
        }
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

    /// Record a decision. Approval triggers execution.
    public func decide(_ rec: Recommendation, _ decision: RecommendationDecision) async {
        rec.decision = decision
        if decision == .approved {
            _ = await execute(rec)
        }
    }

    /// Run an approved recommendation; always produce exactly one OutputCard
    /// per execution (success or failure — no silent completion). Returns the
    /// card so callers (auto-accept) can act on it.
    @discardableResult
    public func execute(_ rec: Recommendation) async -> OutputCard? {
        guard !isExecuting else { return nil }
        isExecuting = true
        currentTitle = rec.title
        rec.executionState = .running
        defer { isExecuting = false; currentTitle = nil }

        let result = await claude(
            VaultSweep.executePrompt(title: rec.title, body: rec.body), rec.vaultPath
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
