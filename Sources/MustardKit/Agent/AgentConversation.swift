import Foundation
import SwiftData

/// Shared append rule for a task's durable conversation so the coordinator (live Claude
/// turns) and `AgentService` (connected-bridge result normalization) allocate message
/// sequence numbers and bump `lastActivityAt` identically — one source of truth for
/// ordering, no duplicated persistence code.
enum AgentConversation {
    @discardableResult
    static func append(
        to run: AgentRun,
        role: AgentMessageRole,
        kind: AgentMessageKind,
        content: String,
        links: [TaskLink] = [],
        now: Date,
        in context: ModelContext
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
}
