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
                actionType: proposal.actionType, vaultPath: vaultPath
            )
            context.insert(rec)
        }
    }

    /// Record a decision. Approval triggers execution.
    public func decide(_ rec: Recommendation, _ decision: RecommendationDecision) async {
        rec.decision = decision
        if decision == .approved {
            await execute(rec)
        }
    }

    /// Run an approved recommendation; always produce exactly one OutputCard
    /// per execution (success or failure — no silent completion).
    public func execute(_ rec: Recommendation) async {
        guard !isExecuting else { return }
        isExecuting = true
        rec.executionState = .running
        defer { isExecuting = false }

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
    }
}
