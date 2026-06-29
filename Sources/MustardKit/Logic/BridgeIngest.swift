import Foundation

public enum BridgeIngest {
    public enum Outcome: Equatable { case applied, staleIgnored, unknownTask }

    /// Apply a result to its task under the stage guard (prep→forAgent, execute→queued).
    /// Mutates `task`. The caller archives the file for EVERY outcome. `failed` leaves the
    /// task at its source stage (so the next export re-issues the work order — retry).
    @discardableResult
    public static func apply(_ r: AgentResult, to task: MustardTask?) -> Outcome {
        guard let task else { return .unknownTask }
        let sourceStage: TaskStage = (r.mode == "prep") ? .forAgent : .queued
        guard task.stage == sourceStage else { return .staleIgnored }

        switch (r.mode, r.status) {
        case ("prep", "done"):
            if let a = r.actionType, !a.isEmpty { task.actionTypeRaw = a }
            if let b = r.body { task.notes = b }
            if let t = r.title, !t.isEmpty { task.title = t }
            task.stage = .needsApproval
        case ("execute", "done"):
            task.links = r.links ?? []
            if let s = r.summary, !s.isEmpty {
                task.notes += (task.notes.isEmpty ? "" : "\n\n") + "🤖 Agent output:\n\(s)"
            }
            task.stage = .needsReview
        case (_, "declined"):
            task.owner = .me; task.stage = .planned
            let why = (r.summary ?? "").isEmpty ? "." : ": \(r.summary!)"
            task.notes += (task.notes.isEmpty ? "" : "\n\n") + "🤖 Agent passed on this\(why)"
        case (_, "failed"):
            break   // stay at source stage; caller surfaces r.error
        default:
            break   // unknown combo: no-op (still archived)
        }
        return .applied
    }
}
