import Foundation

/// Prompt + parser for the vault-source triage sweep.
public enum VaultSweep {
    public static let prompt = """
    You are reviewing a personal Obsidian knowledge base to recommend actionable tasks.
    Look at the notes in this directory: recent changes, stale items, open loops, gaps.
    Ignore these app-internal folders entirely — never read or propose from them:
    `_filed/` (your own filed log), `_recs/` (the email scout's drop folder), `.obsidian/`.
    Recommend up to 5 concrete, actionable tasks that would move this knowledge base's
    owner forward.

    For each, include:
    - action_type: one of vault_note, create_task, draft_email, draft_slack, ticket_write, fyi, ignore
    - confidence: 0.0–1.0, how sure you are this is worth doing
    - reasoning: one sentence on why you propose it
    - draft: the proposed content (the note text, the email body, etc.) — what you'd actually produce

    Respond with ONLY a JSON array, no prose, in this exact shape:
    [{"title": "short imperative title", "body": "1-3 sentences: what and why",
      "action_type": "vault_note", "confidence": 0.8, "reasoning": "why", "draft": "proposed content"}]
    """

    public struct Proposal: Equatable {
        public let title: String
        public let body: String
        public let actionType: String
        public let confidence: Double
        public let reasoning: String
        public let draft: String
    }

    /// Extracts the first JSON array from model output (code-fence tolerant).
    public static func parse(_ text: String) -> [Proposal] {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"), start < end else { return [] }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return raw.prefix(5).compactMap { item in
            guard let title = item["title"] as? String, !title.isEmpty else { return nil }
            let confidence = (item["confidence"] as? NSNumber)?.doubleValue ?? 0.5
            return Proposal(
                title: title,
                body: item["body"] as? String ?? "",
                actionType: item["action_type"] as? String ?? "vault_note",
                confidence: min(max(confidence, 0), 1),
                reasoning: item["reasoning"] as? String ?? "",
                draft: item["draft"] as? String ?? ""
            )
        }
    }

    /// Grounded, action-aware execution prompt. Unlike a generic "do this task",
    /// it tells Claude what kind of deliverable to produce, hands back the draft it
    /// already proposed as the starting point, and — when feedback or a prior output
    /// are present — instructs it to revise rather than start over. Pure: takes the
    /// `RecommendationAction` enum plus primitives so it stays unit-testable.
    public static func executePrompt(
        title: String, body: String, action: RecommendationAction,
        draft: String = "", sourceContext: String = "",
        feedback: String = "", priorOutput: String = ""
    ) -> String {
        var parts: [String] = []
        parts.append("""
        Execute this task against the knowledge base in the current directory.
        \(directive(for: action))

        Task: \(title)

        \(body)
        """)

        let starting = draft.isEmpty ? body : draft
        if !starting.isEmpty {
            parts.append("""
            Starting point (your proposed draft — finalize and improve it, don't restart):
            \(starting)
            """)
        }

        if !sourceContext.isEmpty {
            parts.append("Context: \(sourceContext)")
        }

        if !priorOutput.isEmpty || !feedback.isEmpty {
            var revision = "This is a revision."
            if !priorOutput.isEmpty {
                revision += "\nYou previously produced:\n\(priorOutput)"
            }
            if !feedback.isEmpty {
                revision += "\nRevise per this feedback: \(feedback)"
            } else {
                revision += "\nImprove on the previous attempt."
            }
            revision += "\nReturn the full revised deliverable, not a diff."
            parts.append(revision)
        }

        parts.append("End your response with a concise summary of what you did and any output produced.")
        return parts.joined(separator: "\n\n")
    }

    /// Per-action instruction. Gated actions (email/Slack/ticket) stay draft-only —
    /// execution produces text for review, it never sends or files anything.
    private static func directive(for action: RecommendationAction) -> String {
        switch action {
        case .draftEmail:
            return "Finalize a ready-to-send email (subject line + body) from the draft below. Produce the text only — do not send it."
        case .draftSlack:
            return "Finalize a concise, well-toned Slack message from the draft below. Produce the text only — do not send it."
        case .ticket:
            return "Produce the finalized ticket text (title + description) from the draft below. Produce the text only — do not file it."
        case .createTask:
            return "Produce the finalized task (title + description) from the draft below; do not invent fields."
        case .vaultNote:
            return "Apply this change to the knowledge base, starting from the proposed note text below."
        case .fyi:
            return "Produce the finalized briefing/FYI text from the draft below."
        case .ignore:
            return "No action is needed; briefly note why this was surfaced."
        }
    }
}
